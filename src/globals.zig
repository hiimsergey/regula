const config = @import("config");
const std = @import("std");
const linux = std.os.linux;

const c = @import("c.zig").c;
const constants = @import("constants.zig");
const log = @import("log.zig");

const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");

const Generic = error.Generic;

const LayerSurface = struct {
	// NOTE must keep this field first
	kind: c_uint,

	mon: *Monitor,
	scene: *c.struct_wlr_scene_tree,
	popups: *c.struct_wlr_scene_tree,
	scene_layer: *c.struct_wlr_scene_layer_surface_v1,
	link: c.wl_list,
	mapped: i32,
	layer_surface: *c.wlr_layer_surface_v1
};
const Layout = struct {
	symbol: []const u8,
	arrange: *const fn (*Monitor) void
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
const output_power_mgr_set_mode = c.struct_wl_listener{ .notify = cb_power_mgr_set_mode };

var activation: *c.wlr_xdg_activation_v1 = undefined;
var alloc: *c.struct_wlr_allocator = undefined;
var backend: *c.struct_wlr_backend = undefined;
var compositor: *c.wlr_compositor = undefined;
var display: *c.struct_wl_display = undefined;
var drag_icon: *c.struct_wlr_scene_tree = undefined;
var event_loop: *c.struct_wl_event_loop = undefined;
var layers: [NUM_LAYERS]*c.struct_wlr_scene_tree = undefined;
var mons: c.wl_list = undefined;
var selmon: *Monitor = undefined;
var renderer: *c.struct_wlr_renderer = undefined;
var root_bg: *c.struct_wlr_scene_rect = undefined;
var scene: *c.struct_wlr_scene = undefined;
var session: *c.struct_wlr_session = undefined;

var fstack: c.struct_wl_list = undefined;

var power_mgr: *c.struct_wlr_output_power_manager_v1 = undefined;

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
	backend = c.wlr_backend_autocreate(event_loop, @ptrCast(&session)) orelse {
		log.errln("wlroots: Failed to create backend!", .{});
		return Generic;
	};
	scene = c.wlr_scene_create();
	root_bg = c.wlr_scene_rect_create(&scene.tree, 0, 0, constants.config.rootcolor);

	for (&layers) |*layer| layer.* = c.wlr_scene_tree_create(&scene.tree);
	drag_icon = c.wlr_scene_tree_create(&scene.tree);
	c.wlr_scene_node_place_below(
		&drag_icon.node,
		&layers[@intFromEnum(Layer.block)].node
	);

	renderer = c.wlr_renderer_autocreate(backend) orelse {
		log.errln("wlroots: Failed to create renderer!", .{});
		return Generic;
	};
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

	alloc = c.wlr_allocator_autocreate(backend, renderer) orelse {
		log.errln("wlroots: Failed to create allocator!", .{});
		return Generic;
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
	c.wl_signal_add(&activation.events.request_activate, &request_activate);

	c.wlr_scene_set_gamma_control_manager_v1(
		scene,
		c.wlr_gamma_control_manager_v1_create(display)
	);

	power_mgr = c.wlr_output_power_manager_v1_create(display);
	c.wl_signal_add(&power_mgr.events.set_mode, &output_power_mgr_set_node);

	// TODO NOW
}

fn handlesig(signo: i32) callconv(.c) void {
	var idc: u32 = undefined;
	if (signo == linux.SIG.CHLD)
		while (linux.waitpid(-1, &idc, linux.W.NOHANG) > 0) {} // TODO oh god
	else if (signo == linux.SIG.INT or signo == linux.SIG.TERM)
		c.wl_display_terminate(display);
}

fn cb_gpu_reset(_: ?*c.struct_wl_listener, _: ?*anyopaque) void {
	const old_renderer, const old_alloc = .{ renderer, alloc };
	defer {
		c.wlr_allocator_destroy(old_alloc);
		c.wlr_renderer_destroy(old_renderer);
	}

	renderer = c.wlr_renderer_autocreate(backend) orelse {
		log.errln("wlroots: Failed to create renderer!", .{});
		return Generic;
	};

	alloc = c.wlr_allocator_autocreate(backend, renderer) orelse {
		log.errln("wlroots: Failed to create allocator!", .{});
		return Generic;
	};

	c.wl_list_remove(&gpu_reset.link);
	c.wl_signal_add(&renderer.events.lost, &gpu_reset);

	c.wlr_compositor_set_renderer(compositor, renderer);

	var m: *Monitor = undefined;
	m = c.wl_container_of(mons.next, m, "link");
	while (&m.link != &mons) : (m = c.wl_container_of(m.link.next, m, "link"))
		c.wlr_output_init_render(m.output, alloc, renderer);
}
fn cb_urgent(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(data.?);
	const client: ?*Client = null;
	toplevel_from_wlr_surface(event.surface, &client, null);
	if (client == null or c == selmon.topmost_client()) return;

	client.is_urgent = true;

	if (client.get_surface().mapped)
		client.set_border_color(constants.config.urgentcolor);
}
fn cb_power_mgr_set_mode(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.struct_wlr_output_power_v1_set_mode_event = @ptrCast(data);
	const state: c.wlr_output_state = undefined;
	@memset(state, 0);

	const mon: *Monitor = event.output.*.data orelse return;
	mon.gamma_lut_changed = 1;

	c.wlr_output_state_set_enabled(&state, event.mode);
	c.wlr_output_commit_state(mon.output, &state);

	mon.asleep = !event.mode;
	cb_update_monitors(null, null);
}
fn cb_update_monitors(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const config: *c.struct_wlr_output_configuration_v1 =
		c.wlr_output_configuration_v1_create();
	var config_head: *c.struct_wlr_output_configuration_head_v1 = undefined;

	var m: *Monitor = undefined;
	m = // TODO
}

inline fn toplevel_from_wlr_surface(
	sur: ?*c.wlr_surface,
	cl_ptr: ?**const Client,
	lysur_ptr: ?**const LayerSurface
) i32 {
	var client_type = Client.Type.invalid;
	var client: *Client = undefined;
	var our_ls: *LayerSurface = undefined;

	bod: {
		const root_surface: *c.wlr_surface =
			c.wlr_surface_get_root_surface(sur orelse return -1);

		if (config.xwayland) {
			const xsurface: ?*c.wlr_xwayland_surface =
				c.wlr_xwayland_surface_try_from_wlr_surface(root_surface);
			if (@intFromPtr(xsurface) != 0) {
				client = xsurface.data;
				client_type = client.type;
				break :bod;
			}
		}

		const layer_surface: ?*c.wlr_layer_surface_v1 =
			c.wlr_layer_surface_v1_try_from_wlr_surface(root_surface);
		if (@intFromPtr(layer_surface) != 0) {
			our_ls = layer_surface.data;
			client_type = .layer_shell;
			break :bod;
		}

		// TODO READ can you cast c pointers to optional pointers?
		// ie can you use orelse?
		const xdg_surface: ?*c.wlr_xdg_surface =
			c.wlr_xdg_surface_try_from_wlr_surface(root_surface);
		while (@intFromPtr(xdg_surface) != 0) {
			var tmp_xdgsur: ?*c.wlr_xdg_surface = null;
			switch (xdg_surface.role) {
				c.WLR_XDG_SURFACE_ROLE_POPUP => {
					if (xdg_surface.unnamed_0.popup == null or
						xdg_surface.unnamed_0.popup.*.parent == null)
						return .invalid;

					tmp_xdgsur =
						c.wlr_xdg_surface_try_from_wlr_surface(xdg_surface.unnamed_0.popup.*.parent)
					orelse return toplevel_from_wlr_surface(
						xdg_surface.unnamed_0.popup.*.parent,
						cl_ptr, lysur_ptr
					);

					xdg_surface = tmp_xdgsur;
				},
				c.WLR_XDG_SURFACE_ROLE_TOPLEVEL => {
					client = @ptrCast(xdg_surface.data);
					client_type = client.kind;
					break :bod;
				},
				c.WLR_XDG_SURFACE_ROLE_NONE, _ => return .invalid
			}
		}
	}

	if (lysur_ptr) |pl| pl.* = our_ls;
	if (cl_ptr) |pc| pc.* = client;

	return @intFromEnum(client_type);
}
