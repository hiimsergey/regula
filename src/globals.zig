const config = @import("config");
const std = @import("std");
const linux = std.os.linux;
const log = std.log;
const c = @import("c.zig").c;
const lsrs = @import("listeners.zig");
const userconfig = @import("userconfig.zig");

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

	pub const map = [_]u8{
		@backingInt(Layer.background),
		@backingInt(Layer.bottom),
		@backingInt(Layer.top),
		@backingInt(Layer.overlay)
	};

	const len = @typeInfo(Layer).@"enum".fields.len;
};

// TODO CONSIDER MOVE
const KeyboardGroup = struct {
	interface: c.wlr_keyboard_group,

	n_symbols: c_int,
	key_symbols: *const c.xkb_keysym_t,
	mods: u32,
	key_repeat_source: *const c.wl_event_source,

	modifiers_lsr: c.wl_listener,
	key_lsr: c.wl_listener,
	destroy_lsr: c.wl_listener,

	fn init() *KeyboardGroup {
		const group = gpa.create(KeyboardGroup)
			catch die("Failed to allocate memory!", .{}, 12);
		group.interface = c.wlr_keyboard_group_create();
		group.interface.data = group;

		const ctx: *const c.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
		const keymap: *const c.xkb_keymap = c.xkb_keymap_new_from_names(ctx,
			&userconfig.xkb_rules,
			c.XKB_KEYMAP_COMPILE_NO_FLAGS)
			orelse die("Failed to compile keymap!", .{}, 1);

		c.wlr_keyboard_set_keymap(&group.interface.keyboard, keymap);
		c.xkb_keymap_unref(keymap);
		c.xkb_context_unref(ctx);

		c.wlr_keyboard_set_repeat_info(
			&group.interface.keyboard,
			userconfig.repeat_rate,
			userconfig.repeat_delay);

		listenWrapper(&group.interface.keyboard.events.key, &group.key_lsr, lsrs.keypress);
		listenWrapper(&group.interface.keyboard.events.modifiers, &group.modifiers_lsr, lsrs.keypressMod);

		group.key_repeat_source = c.wl_event_loop_add_timer(event_loop, lsrs.keyRepeat, group);

		c.wlr_seat_set_keyboard(seat, &group.interface.keyboard);
		return group;
	}

	fn destroy(lsr: ?*c.wl_listener, _: ?*anyopaque) void {
		var group: *const KeyboardGroup = undefined;
		group = c.wl_container_of(lsr, group, "destroy");
		c.wl_event_source_remove(group.key_repeat_source);
		c.wl_list_remove(&group.key_lsr.link);
		c.wl_list_remove(&group.modifiers_lsr.link);
		c.wl_list_remove(&group.destroy_lsr.link);
		c.wlr_keyboard_group_destroy(group.interface);
		gpa.free(group);
	}
};

const LayerSurface = struct {
	// NOTE must keep this field first
	// TODO why
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

pub var xwayland: if (config.xwayland) [*c]c.wlr_xwayland else void = undefined;

pub fn init(proc_init: std.process.Init) !void {
	gpa = proc_init.gpa;

	// Reset signal handlers for SIGCHLD, SIGINT, SIGTERM and SIGPIPE
	const sa = linux.Sigaction{
		.flags = linux.SA.RESTART,
		.handler = .{ .handler = handlesig },
		.mask = linux.sigemptyset()
	};

	inline for (&.{
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
	root_bg = c.wlr_scene_rect_create(&scene.tree, 0, 0, &userconfig.root_color);

	for (&layers) |*layer| layer.* = c.wlr_scene_tree_create(&scene.tree);
	drag_icon = c.wlr_scene_tree_create(&scene.tree);
	c.wlr_scene_node_place_below(
		&drag_icon.node,
		&layers[@backingInt(Layer.block)].node
	);

	renderer = c.wlr_renderer_autocreate(backend) orelse {
		log.err("wlroots: Failed to create renderer!", .{});
		return error.Generic;
	};
	c.wl_signal_add(&renderer.events.lost, &lsrs.items.gpu_reset);

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
	c.wl_signal_add(&activation.events.request_activate, &lsrs.request_activate);

	c.wlr_scene_set_gamma_control_manager_v1(
		scene,
		c.wlr_gamma_control_manager_v1_create(display)
	);

	power_mgr = c.wlr_output_power_manager_v1_create(display);
	c.wl_signal_add(&power_mgr.events.set_mode, &lsrs.items.output_power_mgr_set_node);

	output_layout = c.wlr_output_layout_create(display);
	c.wl_signal_add(&output_layout.events.change, &lsrs.items.layout_change);

	c.wlr_xdg_output_manager_v1_create(display, output_layout);

	c.wl_list_init(&monitors);
	c.wl_signal_add(&backend.events.new_output, &lsrs.items.new_output);

	c.wl_list_init(&clients);
	c.wl_list_init(&focus_stack);

	xdg_shell = c.wlr_xdg_shell_create(display, 6);
	c.wl_signal_add(&xdg_shell.events.new_toplevel, &lsrs.items.new_xdg_toplevel);
	c.wl_signal_add(&xdg_shell.events.new_popup, &lsrs.items.new_xdg_popup);

	layer_shell = c.wlr_layer_shell_v1_create(display, 3);
	c.wl_signal_add(&layer_shell.events.new_surface, &lsrs.items.new_layer_surface);

	idle_notifier = c.wlr_idle_notifier_v1_create(display);

	idle_inhibit_mgr = c.wlr_idle_inhibit_v1_create(display);
	c.wl_signal_add(&idle_inhibit_mgr.events.new_inhibitor, &lsrs.items.new_inhibitor);

	session_lock_mgr = c.wlr_session_lock_manager_v1_create(display);
	c.wl_signal_add(&session_lock_mgr.events.new_lock, &lsrs.items.new_session_lock);

	locked_bg = c.wlr_scene_rect_create(
		layers[@backingInt(Layer.block)],
		screen_geom.width, screen_geom.height,
		[_]f32{0.1, 0.1, 0.1, 1.0});
	c.wlr_scene_node_set_enabled(&locked_bg.node, 0);

	c.wlr_server_decoration_manager_set_default_mode(
		c.wlr_server_decoration_manager_create(display),
		c.WLR_SERVER_DECORATION_MANAGER_MODE_SERVER);
	xdg_decoration_mgr = c.wlr_xdg_decoration_manager_v1_create(display);
	c.wl_signal_add(&xdg_decoration_mgr.events.new_toplevel_decoration, &lsrs.items.new_xdg_decoration);

	ptr_constraints = c.wlr_pointer_constraints_v1_create(display);
	c.wl_signal_add(&ptr_constraints.events.new_constraint, &lsrs.items.new_pointer_constraint);

	relative_ptr_mgr = c.wlr_relative_pointer_manager_v1_create(display);

	cursor = c.wlr_cursor_create();
	c.wlr_cursor_attach_output_layout(cursor, output_layout);

	cursor_mgr = c.wlr_xcursor_manager_create(null, 24);
	proc_init.environ_map.put("XCURSOR_SIZE", "24", 1) catch {
		log.err("Failed to change environment variable XCURSOR_SIZE", .{});
		return error.Generic;
	};

	c.wl_signal_add(&cursor.events.motion, &lsrs.items.cursor_motion);
	c.wl_signal_add(&cursor.events.motion_absolute, &lsrs.items.cursor_motion_absolute);
	c.wl_signal_add(&cursor.events.button, &lsrs.items.cursor_button);
	c.wl_signal_add(&cursor.events.axis, &lsrs.items.cursor_axis);
	c.wl_signal_add(&cursor.events.frame, &lsrs.items.cursor_frame);

	cursor_shape_mgr = c.wlr_cursor_shape_manager_v1_create(display, 1);
	c.wl_signal_add(&cursor_shape_mgr.events.request_set_shape, &lsrs.items.request_set_cursor_shape);

	c.wl_signal_add(&backend.events.new_input, &lsrs.items.new_input_device);

	virtual_keyboard_mgr = c.wlr_virtual_keyboard_manager_v1_create(display);
	c.wl_signal_add(&virtual_keyboard_mgr.events.new_virtual_keyboard, &lsrs.items.new_virtal_keyboard);

	virtual_pointer_mgr = c.wlr_virtual_pointer_manager_v1_create(display);
	c.wl_signal_add(&virtual_pointer_mgr.events.new_virtual_pointer, &lsrs.items.new_virtual_pointer);

	seat = c.wlr_seat_create(display, "seat0");
	c.wl_signal_add(&seat.events.request_set_cursor, &lsrs.items.request_cursor);
	c.wl_signal_add(&seat.events.request_set_selection, &lsrs.items.request_set_sel);
	c.wl_signal_add(&seat.events.request_set_primary_selection, &lsrs.items.request_set_psel);
	c.wl_signal_add(&seat.events.request_start_drag, &lsrs.items.request_start_drag);
	c.wl_signal_add(&seat.events.start_drag, &lsrs.items.start_drag);

	kb_group = KeyboardGroup.init();
}

pub fn deinit() void {
	lsrs.deinit();
	if (config.xwayland) {
		c.wlr_xwayland_destroy(xwayland);
		xwayland = null;
	}

	c.wl_display_destroy_clients(display);
	if (child_pid > 0) {
		var idc: u32 = undefined;
		_ = linux.kill(-child_pid, linux.SIG.TERM);
		_ = linux.waitpid(child_pid, &idc, 0);
	}
	c.wlr_xcursor_manager_destroy(cursor_mgr);

	KeyboardGroup.destroy(&kb_group.destroy_lsr, null);

	// If it's not destroyed manually, it will cause a use-after-free of wlr_seat.
	// Destroy it until it's fixed on the wlroots side.
	c.wlr_backend_destroy(backend);

	c.wl_display_destroy(display);
	// Destroy after the wayland display (when the monitors are already destroyed)
	// to avoid destroying them with an invalid scene output.
	c.wlr_scene_node_destroy(&scene.tree.node);
}

pub fn die(comptime fmt: []const u8, args: anytype, comptime stat: u8) noreturn {
	log.err(fmt, args);
	deinit();
	std.process.exit(stat);
}

pub fn listenWrapper(
	event: [*c]c.wl_signal,
	lsr: *c.wl_listener,
	handler: fn ([*]c.wl_listener, ?*anyopaque) callconv(.c) void
) void {
	lsr.notify = handler;
	c.wl_signal_add(event, @ptrCast(lsr));
}

fn handlesig(signo: i32) callconv(.c) void {
	var idc: u32 = undefined;
	if (signo == @backingInt(linux.SIG.CHLD))
		while (linux.waitpid(-1, &idc, linux.W.NOHANG) > 0) {}
	else if (signo == @backingInt(linux.SIG.INT) or signo == @backingInt(linux.SIG.TERM))
		c.wl_display_terminate(display);
}
