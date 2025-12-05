const config = @import("config");
const std = @import("std");
const linux = std.os.linux;

const c = @import("c.zig").c;
const constants = @import("constants.zig");
const log = @import("log.zig");

const Generic = error.Generic;

const Client = struct {
	kind: ClientType,
	mon: *Monitor,
	scene: *c.struct_wlr_scene_tree,
	border: [4]*c.struct_wlr_scene_rect, // top, bottom, left, right
	scene_surface: *c.struct_wlr_scene_tree,
	link: c.struct_wl_list,
	flink: c.struct_wl_list,
	geom: c.struct_wlr_box,
	prev: c.struct_wlr_box,
	bounds: c.struct_wlr_box,
	surface: union {
		xdg: *c.wlr_xdg_surface,
		xwayland: *c.struct_wlr_xwayland_surface
	},
	decoration: *c.struct_wlr_xdg_toplevel_decoration_v1,
	commit: c.struct_wl_listener,
	map: c.struct_wl_listener,
	maximize: c.struct_wl_listener,
	unmap: c.struct_wl_listener,
	destroy: c.struct_wl_listener,
	set_title: c.struct_wl_listener,
	fullscreen: c.struct_wl_listener,
	set_decoration_mode: c.struct_wl_listener,
	destroy_decoration: c.struct_wl_listener,

	bw: u32,
	tags: u32,
	// TODO CONSIDER bit field
	is_floating: bool,
	is_urgent: bool,
	is_fullscreen: bool,
	resize: u32,

	xwayland: if (config.xwayland) struct {
		activate: c.struct_wlr_listener,
		associate: c.struct_wlr_listener,
		dissociate: c.struct_wlr_listener,
		configure: c.struct_wlr_listener,
		set_hints: c.struct_wlr_listener,
	} else void,

	fn get_surface(self: *const Client) ?c.struct_wlr_surface {
		if (config.xwayland and self.kind == .x11)
			return self.surface.xwayland.surface;
		return self.surface.xdg.surface;
	}

	fn set_border_color(self: *const Client, hex: comptime_int) void {
		const col = color(hex);
		for (0..4) |i| c.wlr_scene_rect_set_color(self.border[i], col);
	}

	fn visible_on(self: *const Client, mon: ?*const Monitor) bool {
		return mon != null and self.mon == mon and
			@intFromBool(self.tags & mon.?.tagset[mon.?.seltags]);
	}
};
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
	asleep: i32,

	fn topmost_client(self: *Monitor) ?*Client {
		var cl: *Client = undefined;
		cl = c.wl_container_of(fstack.next, cl, "flink");
		while (&cl.flink != &fstack) : (cl = c.wl_container_of(cl.flink.next, cl, "flink"))
			if (cl.visible_on(self)) return cl;
		return null;
	}

// TODO for (c = wl_container_of((fstack)->next, c, flink);    \
// TODO      &c->flink != (fstack);                    \
// TODO      c = wl_container_of(c->flink.next, c, flink))
// TODO }
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

const ClientType = enum(i8) {invalid, xdg_shell, layer_shell, x11};

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
var selmon: *Monitor = undefined;
var renderer: *c.struct_wlr_renderer = undefined;
var root_bg: *c.struct_wlr_scene_rect = undefined;
var scene: *c.struct_wlr_scene = undefined;
var session: *c.struct_wlr_session = undefined;

var fstack: c.struct_wl_list = undefined;

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

	const bg: [4]f32 = color(constants.config.rootcolor);
	root_bg = c.wlr_scene_rect_create(&scene.tree, 0, 0, &bg);

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
}

fn handlesig(signo: i32) callconv(.c) void {
	var idc: u32 = undefined;
	if (signo == linux.SIG.CHLD)
		while (linux.waitpid(-1, &idc, linux.W.NOHANG) > 0) {} // TODO oh god
	else if (signo == linux.SIG.INT or signo == linux.SIG.TERM)
		c.wl_display_terminate(display);
}

// TODO CONSIDER REMOVE
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

fn cb_urgent(_: *c.wl_listener, data: *anyopaque) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(data);
	const client: ?*Client = null;
	toplevel_from_wlr_surface(event.surface, &client, null);
	if (client == null or c == selmon.topmost_client()) return;

	client.is_urgent = true;

	if (client.get_surface().mapped)
		client.set_border_color(constants.config.urgentcolor);
}

inline fn toplevel_from_wlr_surface(
	sur: ?*c.wlr_surface,
	cl_ptr: ?**const Client,
	lysur_ptr: ?**const LayerSurface
) i32 {
	var client_type = ClientType.invalid;
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
