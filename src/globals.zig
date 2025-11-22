const config = @import("config");
const std = @import("std");
const linux = std.os.linux;

const c = @import("c.zig").c;
const constants = @import("constants.zig");
const log = @import("log.zig");

const Generic = error.Generic;

const Layout = struct {
	symbol: []const u8,
	arrange: *const fn (*Monitor) void
};

const Monitor = struct {
	link: c.wl_list,
	output: *c.wlr_output,
	scene_output: *c.wlr_scene_output,
	fullscreen_bg: *c.wlr_scene_rect,
	frame: c.wl_listener,
	destroy: c.wl_listener,
	request_state: c.wl_listener,
	destroy_lock_surface: c.wl_listener,
	lock_surface: *c.wlr_session_lock_surface_v1,
	monitor: c.wlr_box,
	window: c.wlr_box,
	layers: c.wl_list[4],
	layout: [2]*Layout,
	seltags: u32,
	sellt: u32,
	tagset: [2]u32,
	mfact: f32,
	gamma_lut_changed: i32,
	nmaster: i32,
	ltsymbol: [16]u8,
	asleep: i32
};

const Layer = enum(u8) {
	background,
	bottom,
	tile,
	float,
	top,
	fs,
	overlay,
	block
};
const NUM_LAYERS = @typeInfo(Layer).@"enum".fields.len;

const gpu_reset = c.struct_wl_listener{ .notify = cb_gpu_reset };
const request_activate = c.struct_wl_listener{ .notify = cb_urgent };

var activation: *c.wlr_xdg_activation_v1 = undefined;
var alloc: *c.struct_wlr_allocator = undefined;
var backend: *c.struct_wlr_backend = undefined;
var compositor: *c.wlr_compositor = undefined;
var display: *c.struct_wl_display = undefined;
var drag_icon: *c.struct_wlr_scene_tree = undefined;
var event_loop: *c.struct_wl_event_loop = undefined;
var layers: [NUM_LAYERS]*c.struct_wlr_scene_tree = undefined;
var mons: c.wl_list = undefined;
var renderer: *c.struct_wlr_renderer = undefined;
var root_bg: *c.struct_wlr_scene_rect = undefined;
var scene: *c.struct_wlr_scene = undefined;
var session: *c.struct_wlr_session = undefined;

pub fn init() !void {
	// Reset signal handlers for SIGCHLD, SIGINT, SIGTERM and SIGPIPE
	const sa = linux.Sigaction{
		.flags = linux.SA.RESTART,
		.handler = .{ .handler = handlesig },
		.mask = undefined
	};
	_ = linux.sigemptyset();

	inline for ([_]comptime_int{
		linux.SIG.CHLD,
		linux.SIG.INT,
		linux.SIG.TERM,
		linux.SIG.PIPE,
	}) |sig| _ = linux.sigaction(sig, &sa, null);

	c.wlr_log_init(c.WLR_ERROR, null);

	display = c.wl_display_create() orelse return Generic;
	event_loop = c.wl_display_get_event_loop(display) orelse return Generic;
	
	backend = c.wlr_backend_autocreate(event_loop, @ptrCast(&session));
	if (@intFromPtr(backend) == 0) {
		log.errln("wlroots: Failed to create backend!", .{});
		return Generic;
	}

	scene = c.wlr_scene_create();

	const bg: [4]f32 = color(constants.config.rootcolor);
	root_bg = c.wlr_scene_rect_create(&scene.tree, 0, 0, &bg);

	for (&layers) |*layer| layer.* = c.wlr_scene_tree_create(&scene.tree);
	drag_icon = c.wlr_scene_tree_create(&scene.tree);
	c.wlr_scene_node_place_below(
		&drag_icon.node,
		&layers[@intFromEnum(Layer.block)].node
	);

	renderer = c.wlr_renderer_autocreate(backend);
	if (@intFromPtr(renderer) == 0) {
		log.errln("wlroots: Failed to create renderer!", .{});
		return Generic;
	}
	c.wl_signal_add(&renderer.events.lost, &gpu_reset);

	c.wlr_renderer_init_wl_shm(renderer, display);

	if (c.wlr_renderer_get_texture_formats(display, c.WLR_BUFFER_CAP_DMABUF)) {
		c.wlr_drm_create(display, renderer);
		c.wlr_scene_set_linux_dmabuf_v1(scene,
			c.wlr_linux_dmabuf_v1_create_with_renderer(display, 5, renderer));
	}

	const drm: c_int = c.wlr_renderer_get_drm_fd(renderer);
	if (drm >= 0 and renderer.features.timeline and backend.features.timeline)
		c.wlr_linux_drm_syncobj_manager_v1_create(display, 1, drm);

	alloc = c.wlr_allocator_autocreate(backend, renderer);
	if (@intFromPtr(alloc) == 0) {
		log.errln("wlroots: Failed to create allocator!", .{});
		return Generic;
	}

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
	c.wl_signal_add(&activation.events.request_activate, &request_activate);
}

fn handlesig(signo: i32) callconv(.c) void {
	var idc: u32 = undefined;
	if (signo == linux.SIG.CHLD)
		while (linux.waitpid(-1, &idc, linux.W.NOHANG) > 0) {} // TODO oh god
	else if (signo == linux.SIG.INT or signo == linux.SIG.TERM)
		c.wl_display_terminate(display);
}

fn color(hex: comptime_int) [4]f32 {
	std.debug.assert(hex >= 0 and hex < 0xff_ff_ff_ff);
	return .{
		(hex >> 24) & 0xff / 255,
		(hex >> 16) & 0xff / 255,
		(hex >> 8) & 0xff / 255,
		(hex & 0xff) / 255,
	};
}

fn cb_gpu_reset(_: *c.struct_wl_listener, _: *anyopaque) void {
	const old_renderer, const old_alloc = .{ renderer, alloc };
	defer {
		c.wlr_allocator_destroy(old_alloc);
		c.wlr_renderer_destroy(old_renderer);
	}

	renderer = c.wlr_renderer_autocreate(backend);
	if (@intFromPtr(renderer) == 0) {
		log.errln("wlroots: Failed to create renderer!", .{});
		return Generic;
	}

	alloc = c.wlr_allocator_autocreate(backend, renderer);
	if (@intFromPtr(alloc) == 0) {
		log.errln("wlroots: Failed to create allocator!", .{});
		return Generic;
	}

	c.wl_list_remove(&gpu_reset.link);
	c.wl_signal_add(&renderer.events.lost, &gpu_reset);

	c.wlr_compositor_set_renderer(compositor, renderer);

	var m: *Monitor = undefined;
	m = c.wl_container_of(mons.next, m, "link");
	while (&m.link != &mons) : (m = c.wl_container_of(m.link.next, m, "link"))
		c.wlr_output_init_render(m.output, alloc, renderer);
}

fn cb_urgent(_: *c.wl_listener, data: *anyopaque) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(data);
	const client: ?*Client = null;
	toplevel_from_wlr_surface(event.surface, &client, null);
	if (client == null or c == focus_top(selmon)) return;

	client.is_urgent = true;
	print_status();

	if (client_surface(client).mapped)
		client_set_border_color(client, constants.config.urgentcolor);
	// TODO NOW PLAN
	// write urgentcolor
	// write Client
	// write LayerSurface
}

inline fn toplevel_from_wlr_surface(
	sur: ?*c.wlr_surface,
	cl_ptr: ?**const Client,
	lysur_ptr: ?**const LayerSuface
) i32 {
	defer {
		if (lysur_ptr) |pl| pl.* = layer_surface;
		if (cl_ptr) |pc| pc.* = client;
		return client_type;
	}

	const xdg_surface: *c.wlr_xdg_surface = undefined;
	const tmp_xdg_surface: *c.wlr_xdg_surface = undefined;
	const layer_surface: *c.wlr_layer_surface_v1 = undefined;

	const layer_surface: *LayerSurface = null;
	var client_type: i32 = -1;

	const root_surface: *c.wlr_surface =
		c.wlr_surface_get_root_surface(sur orelse return -1);

	if (config.xwayland) {
		const xsurface: *c.wlr_xwayland_surface =
			c.wlr_xwayland_surface_try_from_wlr_surface(root_surface);
		if (@intFromPtr(xsurface) != 0) {
			const client: *Client = xsurface.data;
			client_type = client.type;
			return;
		}
	}
}
