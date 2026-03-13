const config = @import("config");
const std = @import("std");
const linux = std.os.linux;
const log = std.log;
const c = @import("c.zig").c;
const listeners = @import("listeners.zig");
const userconfig = @import("userconfig.zig");

const AllocatorWrapper = @import("AllocatorWrapper.zig");
const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");

pub const Layer = enum(u8) {
	background,
	bottom,
	tile,
	float,
	top,
	fs,
	overlay,
	block,

	const len = @typeInfo(Layer).@"enum".fields.len;
	const map = [_]u8{
		@intFromEnum(Layer.background),
		@intFromEnum(Layer.bottom),
		@intFromEnum(Layer.top),
		@intFromEnum(Layer.overlay)
	};
};

// TODO CONSIDER MOVE
const KeyboardGroup = struct {
	interface: c.wlr_keyboard_group,

	symbol_nr: c_int,
	key_symbols: *const c.xkb_keysym_t,
	mods: u32,

	modifiersFn: c.wl_listener,
	keyFn: c.wl_listener,
	destroyFn: c.wl_listener
};

const LayerSurface = struct {
	// TODO why
	// NOTE must keep this field first
	kind: c_uint,

	mon: *Monitor,
	scene: *c.wlr_scene_tree,
	popups: *c.wlr_scene_tree,
	scene_layer: *c.wlr_scene_layer_surface_v1,
	link: c.wl_list,
	mapped: i32,
	layer_surface: *c.wlr_layer_surface_v1
};

const GrabClient = struct {
	interface: *Client,
	x: c_int,
	y: c_int
};

pub var aw: AllocatorWrapper = undefined;
pub var gpa: std.mem.Allocator = undefined;

pub var child_pid: linux.pid_t = -1;
pub var locked: c_int = undefined;
pub var exclusive_focus: *anyopaque = undefined;
pub var display: *c.wl_display = undefined;
pub var event_loop: *c.wl_event_loop = undefined;
pub var backend: *c.wlr_backend = undefined;
pub var scene: *c.wlr_scene = undefined;
pub var layers: [Layer.len]*c.wlr_scene_tree = undefined;
pub var drag_icon: *c.wlr_scene_tree = undefined;
pub var renderer: *c.wlr_renderer = undefined;
pub var alloc: *c.wlr_allocator = undefined;
pub var compositor: *c.wlr_compositor = undefined;
pub var session: *c.wlr_session = undefined;

pub var xdg_shell: *c.wlr_xdg_shell = undefined;
pub var activation: *c.wlr_xdg_activation_v1 = undefined;
pub var xdg_decoration_mgr: *c.wlr_xdg_decoration_manager_v1 = undefined;
pub var clients: c.wl_list = undefined;
pub var focus_stack: c.wl_list = undefined;
pub var idle_notifier: *c.wlr_idle_notifier_v1 = undefined;
pub var idle_inhibit_mgr: *c.wlr_idle_inhibit_manager_v1 = undefined;
pub var layer_shell: *c.wlr_layer_shell_v1 = undefined;
pub var output_mgr: *c.wlr_output_manager_v1 = undefined;
pub var virtual_keyboard_mgr: *c.wlr_virtual_keyboard_manager_v1 = undefined;
pub var virtual_pointer_mgr: *c.wlr_virtual_pointer_manager_v1 = undefined;
pub var cursor_shape_mgr: *c.wlr_cursor_shape_manager_v1 = undefined;
pub var power_mgr: *c.wlr_output_power_manager_v1 = undefined;

pub var ptr_constraints: *c.wlr_pointer_constraints_v1 = undefined;
pub var relative_ptr_mgr: *c.wlr_relative_pointer_manager_v1 = undefined;
pub var active_constraint: *c.wlr_pointer_constraint_v1 = undefined;

pub var cursor: *c.wlr_cursor = undefined;
pub var cursor_mgr: *c.wlr_xcursor_manager = undefined;

pub var root_bg: *c.wlr_scene_rect = undefined;
pub var session_lock_mgr: *c.wlr_session_lock_manager_v1 = undefined;
pub var locked_bg: *c.wlr_scene_rect = undefined;
pub var cur_lock: *c.wlr_session_lock_v1 = undefined;

pub var seat: *c.wlr_seat = undefined;
pub var kb_group: KeyboardGroup = undefined;
pub var cursor_mode: c_uint = undefined;
pub var grab_client: *GrabClient = undefined;

pub var output_layout: *c.wlr_output_layout = undefined;
pub var screen_geom: c.wlr_box = undefined;
pub var monitors: c.wl_list = undefined;
pub var sel_monitor: ?*Monitor = undefined;

pub fn init() !void {
	aw = AllocatorWrapper.init();
	gpa = aw.allocator(std.heap.c_allocator);

	// Reset signal handlers for SIGCHLD, SIGINT, SIGTERM and SIGPIPE
	const sa = linux.Sigaction{
		.flags = linux.SA.RESTART,
		.handler = .{ .handler = handlesig },
		.mask = linux.sigemptyset()
	};

	inline for ([_]comptime_int{
		linux.SIG.CHLD,
		linux.SIG.INT,
		linux.SIG.TERM,
		linux.SIG.PIPE,
	}) |sig| _ = linux.sigaction(sig, &sa, null);

	c.wlr_log_init(c.WLR_ERROR, null);

	display = c.wl_display_create().?;
	event_loop = c.wl_display_get_event_loop(display).?;
	backend = c.wlr_backend_autocreate(event_loop, @ptrCast(&session)) orelse {
		log.err("wlroots: Failed to create backend!", .{});
		return error.Generic;
	};
	scene = c.wlr_scene_create();
	root_bg = c.wlr_scene_rect_create(&scene.tree, 0, 0, userconfig.root_color);

	for (&layers) |*layer| layer.* = c.wlr_scene_tree_create(&scene.tree);
	drag_icon = c.wlr_scene_tree_create(&scene.tree);
	c.wlr_scene_node_place_below(
		&drag_icon.node,
		&layers[@intFromEnum(Layer.block)].node
	);

	renderer = c.wlr_renderer_autocreate(backend) orelse {
		log.err("wlroots: Failed to create renderer!", .{});
		return error.Generic;
	};
	c.wl_signal_add(&renderer.events.lost, &listeners.gpu_reset);

	c.wlr_renderer_init_wl_shm(renderer, display);

	if (c.wlr_renderer_get_texture_formats(display, c.WLR_BUFFER_CAP_DMABUF)) {
		c.wlr_drm_create(display, renderer);
		c.wlr_scene_set_linux_dmabuf_v1(scene,
			c.wlr_linux_dmabuf_v1_create_with_renderer(display, 5, renderer));
	}

	const drm: c_int = c.wlr_renderer_get_drm_fd(renderer);
	if (drm >= 0 and renderer.features.timeline and backend.features.timeline)
		c.wlr_linux_drm_syncobj_manager_v1_create(display, 1, drm);

	alloc = c.wlr_allocator_autocreate(backend, renderer) orelse {
		log.err("wlroots: Failed to create allocator!", .{});
		return error.Generic;
	};

	compositor = c.wlr_compositor_create(display, 6, renderer);
	c.wlr_subcompositor_create(display);
	c.wlr_data_device_manager_create(display);
	c.wlr_export_dmabuf_manager_v1_create(display);
	c.wlr_screencopy_manager_v1_create(display);
	c.wlr_data_control_manager_v1_create(display);
	c.wlr_primary_selection_v1_device_manager_create(display);
	c.wlr_viewporter_create(display);
	c.wlr_single_pixel_buffer_manager_v1_create(display);
	c.wlr_fractional_scale_manager_v1_create(display, 1);
	c.wlr_presentation_create(display, backend, 2);
	c.wlr_alpha_modifier_v1_create(display);

	activation = c.wlr_xdg_activation_v1_create(display);
	c.wl_signal_add(&activation.events.request_activate, &listeners.request_activate);

	c.wlr_scene_set_gamma_control_manager_v1(
		scene,
		c.wlr_gamma_control_manager_v1_create(display)
	);

	power_mgr = c.wlr_output_power_manager_v1_create(display);
	c.wl_signal_add(&power_mgr.events.set_mode, &listeners.output_power_mgr_set_node);

	output_layout = c.wlr_output_layout_create(display);
	c.wl_signal_add(&output_layout.events.change, &listeners.layout_change);

	c.wlr_xdg_output_manager_v1_create(display, output_layout);

	c.wl_list_init(&monitors);
	c.wl_signal_add(&backend.events.new_output, &listeners.new_output);

	c.wl_list_init(&clients);
	c.wl_list_init(&focus_stack);

	xdg_shell = c.wlr_xdg_shell_create(display, 6);
	c.wl_signal_add(&xdg_shell.events.new_toplevel, &listeners.new_xdg_toplevel);
	c.wl_signal_add(&xdg_shell.events.new_popup, &listeners.new_xdg_popup);

	layer_shell = c.wlr_layer_shell_v1_create(display, 3);
	c.wl_signal_add(&layer_shell.events.new_surface, &listeners.new_layer_surcace);
}

pub fn deinit() void {
	aw.deinit();
	// TODO CONSIDER freeing global stuff here
}

pub fn die(comptime fmt: []const u8, args: anytype) void {
	log.err(fmt, args);
	deinit();
	std.process.exit(1);
}

pub fn listenWrapper(
	event: c.wl_signal,
	listener: c.wl_listener,
	handler: fn (c.wl_listener, *anyopaque) void
) void {
	listener.notify = handler;
	c.wl_signal_add(event, handler, listener);
}

fn handlesig(signo: i32) callconv(.c) void {
	var idc: u32 = undefined;
	if (signo == linux.SIG.CHLD)
		while (linux.waitpid(-1, &idc, linux.W.NOHANG) > 0) {}
	else if (signo == linux.SIG.INT or signo == linux.SIG.TERM)
		c.wl_display_terminate(display);
}
