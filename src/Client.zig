// TODO FINAL FIX pub and private fn decls
// TODO FINAL FIX inline and not-inline fn decls

const config = @import("config");
const std = @import("std");
const linux = std.os.linux; // TODO CONSIDER
const c = @import("c.zig").c;
const ctx = @import("globals.zig");

const LayerSurface = @import("LayerSurface.zig");
const Monitor = @import("Monitor.zig");
const Self = @This();

// TODO CONSIDER
pub const Type = enum(i8) {invalid = -1, xdg_shell, layer_shell, x11};

mon: ?*Monitor,
scene: *c.wlr_scene_tree,
border: [4]*c.wlr_scene_rect, // top, bottom, left, right
scene_surface: *c.wlr_scene_tree,
link: c.wl_list,
flink: c.wl_list,
geom: c.wlr_box,
prev: c.wlr_box,
bounds: c.wlr_box,
surface: union(enum) {
	xdg: *c.wlr_xdg_surface,
	xwayland: *c.wlr_xwayland_surface
},
decoration: *c.wlr_xdg_toplevel_decoration_v1,
commit: c.wl_listener,
map: c.wl_listener,
maximize: c.wl_listener,
unmap: c.wl_listener,
destroy: c.wl_listener,
set_title: c.wl_listener,
fullscreen: c.wl_listener,
set_decoration_mode: c.wl_listener,
destroy_decoration: c.wl_listener,

bw: u32,
tags: u32,
is: packed struct(u8) {
	floating: bool,
	urgent: bool,
	fullscreen: bool,
	_: u5 = 0
},
resize_to: u32,

xwayland: if (config.xwayland) struct {
	activate: c.wl_listener,
	associate: c.wl_listener,
	dissociate: c.wl_listener,
	configure: c.wl_listener,
	set_hints: c.wl_listener,
} else void,

pub fn focus(self: *const Self, list: c_int) void {
	// TODO CONSIDER change returntype
	// TODO
	_ = self;
	_ = list;
}

pub fn notifyEnter(surface: *const c.wlr_surface, keyboard: ?*const c.wlr_keyboard) void {
	if (keyboard) |kb| {
		c.wlr_seat_keyboard_notify_enter(
			ctx.seat,
			surface,
			kb.keycodes, kb.num_keycodes, &kb.modifiers
		);
	} else {
		c.wlr_seat_keyboard_notify_clear_focus(ctx.seat, surface, null, 0, null);
	}
}

pub fn toplevelFromWlrSurface(
	sur: ?*c.wlr_surface,
	cl_ptr: ?**const Self,
	lysur_ptr: ?**const LayerSurface
) Type {
	var client_type = Type.invalid;
	var client: *Self = undefined;
	var our_ls: *LayerSurface = undefined;

	body: {
		const root_surface: *c.wlr_surface =
			c.wlr_surface_get_root_surface(sur orelse return .invalid);

		if (config.xwayland) {
			const xsurface: ?*c.wlr_xwayland_surface =
				c.wlr_xwayland_surface_try_from_wlr_surface(root_surface);
			if (@intFromPtr(xsurface) != 0) {
				client = @alignCast(@ptrCast(xsurface.?.*.data.?));
				client_type = switch (client.surface) {
					.xdg => .xdg_shell,
					.xwayland => .x11
				};
				break :body;
			}
		}

		const layer_surface: ?*c.wlr_layer_surface_v1 =
			c.wlr_layer_surface_v1_try_from_wlr_surface(root_surface);
		if (@intFromPtr(layer_surface) != 0) {
			our_ls = @alignCast(@ptrCast(layer_surface.?.*.data.?));
			client_type = .layer_shell;
			break :body;
		}

		const xdg_surface: ?*c.wlr_xdg_surface =
			c.wlr_xdg_surface_try_from_wlr_surface(root_surface);
		while (xdg_surface) |*xdgsur| {
			var tmp_xdgsur: ?*c.wlr_xdg_surface = null;
			switch (xdgsur.role) {
				c.WLR_XDG_SURFACE_ROLE_POPUP => {
					if (xdgsur.unnamed_0.popup == null or
						xdgsur.unnamed_0.popup.*.parent == null)
						return .invalid;

					tmp_xdgsur =
						c.wlr_xdg_surface_try_from_wlr_surface(xdgsur.unnamed_0.popup.*.parent)
					orelse return toplevelFromWlrSurface(
						xdgsur.unnamed_0.popup.*.parent,
						cl_ptr, lysur_ptr
					);

					xdgsur.* = tmp_xdgsur;
				},
				c.WLR_XDG_SURFACE_ROLE_TOPLEVEL => {
					client = @ptrCast(xdgsur.data);
					client_type = switch (client.surface) {
						.xdg => .xdg_shell,
						.xwayland => .x11
					};
					break :body;
				},
				c.WLR_XDG_SURFACE_ROLE_NONE => return .invalid,
				else => unreachable
			}
		}
	}

	if (lysur_ptr) |pl| pl.* = our_ls;
	if (cl_ptr) |pc| pc.* = client;

	return client_type;
}

pub fn activateSurface(surface: [*c]c.wlr_surface, activated: bool) void {
	if (config.xwayland) ifc: {
		const xsurface: *const c.wlr_xwayland_surface =
			c.wlr_xwayland_surface_try_from_wlr_surface(surface) orelse break :ifc;
		c.wlr_xwayland_surface_activate(xsurface, activated);
		return;
	}

	const toplevel: *const c.wlr_xdg_toplevel =
		c.wlr_xdg_toplevel_try_from_wlr_surface(surface) orelse return;
	c.wlr_xdg_toplevel_set_activated(toplevel, activated);
}

fn setBounds(self: *const Self, w: i32, h: i32) u32 {
	if (config.xwayland and self.surface == .xwayland) return 0;

	if (c.wl_resource_get_version(self.surface.xdg.unnamed_0.toplevel.*.resource) <
		c.XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION or w < 0 or h < 0 or
		(self.bounds.width == w and self.bounds.height == h))
		return 0;

	self.bounds.width = w;
	self.bounds.height = h;
	return c.wlr_xdg_toplevel_set_bounds(self.surface.xdg.unnamed_0.toplevel, w, h);
}

fn getAppId(self: *const Self) [*]const u8 {
	const broken: [*]const u8 = "broken";
	if (config.xwayland and self.surface == .xwayland)
		return if (self.surface.xwayland.class) |cls| cls else broken;
	return if (self.surface.xdg.unnamed_0.toplevel.*.app_id) |appid| appid else broken;
}

fn getClip(self: *const Self) c.wlr_box {
	var result = self.wlr_box{
		.x = 0, .y = 0,
		.width = self.geom.width - self.bw,
		.height = self.geom.height - self.bw,
	};
	if (config.xwayland and self.surface == .xwayland) return result;

	result.x = self.surface.xdg.geometry.x;
	result.y = self.surface.xdg.geometry.y;
	return result;
}

fn getGeometry(self: *const Self) c.wlr_box {
	if (config.xwayland and self.surface == .xwayland) {
		const xw = &self.surface.xwayland;
		return .{
			.x = xw.x, .y = xw.y,
			.width = xw.width, .height = xw.height
		};
	}
	return self.surface.xdg.geometry;
}

fn getParent(self: *const Self) ?*Self {
	var result: ?*Self = null;
	if (config.xwayland and self.surface == .xwayland) {
		if (self.surface.xwayland.parent != null)
			_ = toplevelFromWlrSurface(self.surface.xwayland.parent.surface,
				&result, null);
		return result;
	}
	if (self.surface.xdg.unnamed_0.toplevel.*.parent)
		_ = toplevelFromWlrSurface(
			self.surface.xdg.unnamed_0.toplevel.*.parent.*.base.*.surface,
			&result, null);
	return result;
}

fn hasChildren(self: *const Self) bool {
	if (config.xwayland and self.surface == .xwayland)
		return !c.wl_list_empty(&self.surface.xwayland.children);
	// `surface.xdg->link` is never empty because it always contains at least the
	// surface itself.
	return c.wl_list_length(&self.surface.xdg.link) > 1;
}

fn getTitle(self: *const Self) [*]const u8 {
	const broken = "broken";
	if (config.xwayland and self.surface == .xwayland)
		return if (self.surface.xwayland.title) |title| title else broken;
	return if (self.surface.xdg.unnamed_0.toplevel.*.title) |title| title else broken;
}

fn isFloatType(self: *const Self) bool {
	if (config.xwayland and self.surface == .xwayland) {
		const surface: *const c.wlr_xwayland_surface = self.surface.xwayland;
		const hints: *const c.xcb_size_hints_t = surface.size_hints;
		if (surface.modal) return true;

		for (&.{
			c.WLR_XWAYLAND_NET_WM_WINDOW_TYPE_DIALOG,
			c.wLR_XWAYLAND_NET_WM_WINDOW_TYPE_SPLASH,
			c.wLR_XWAYLAND_NET_WM_WINDOW_TYPE_TOOLBAR,
			c.wLR_XWAYLAND_NET_WM_WINDOW_TYPE_UTILITY
		}) |kind| if (c.wlr_xwayland_surface_has_window_type(surface, kind)) return 1;

		const hints_initialized = hints != null and hints.?.min_width > 0 and hints.?.max_height > 0;
		return hints_initialized and
			(hints.max_width == hints.min_width or hints.max_height == hints.min_height);
	}

	const toplevel = self.surface.xdg.unnamed_0.toplevel;
	const state = toplevel.*.current;

	const toplevel_has_parent = toplevel.*.parent != null;
	const state_has_min_side = state.min_width != 0 and state.min_width != 0;
	return toplevel_has_parent or (state_has_min_side and
		(state.min_width == state.max_width or state.min_height == state.max_height));
}

fn isOnMonitor(self: *const Self, monitor: *const Monitor) bool {
	// TODO
	_ = self;
	_ = monitor;
}

fn isStopped(self: *const Self) bool {
	if (config.xwayland and self.surface == .xwayland) return false;

	var pid: c_int = undefined;
	var in = std.mem.zeroes(linux.siginfo_t);
	const flag = linux.W.NOHANG | linux.W.CONTINUED | linux.W.STOPPED | linux.W.NOWAIT;
	c.wl_client_get_credentials(self.surface.xdg.client, &pid, null, null);
	if (linux.waitpid(linux.P.PID, pid, &in, flag) < 0) {
		// This process is not our child process, while is very unlikely that
		// it is stopped, in order to do not skip frames, assume that it is.
		const errno = std.posix.errno(-1);
		if (errno == .ECHILD) return true;
	}
	else if (in.si_pid and
		(in.si_code == linux.W.STOPPED or in.si_code == linux.W.TRAPPED)) return true;

	return false;
}

fn isUnmanaged(self: *const Self) bool {
	return if (config.xwayland and self.surface == .xwayland)
		self.surface.xwayland.override_redirect
		else false;
}

// TODO NOW NOW

pub fn visibleOn(self: *const Self, mon: ?*const Monitor) bool {
	return mon != null and self.mon == mon and
		(self.tags & mon.?.tagset[mon.?.seltags]) == 1;
}

pub fn resize(self: *const Self, geom: c.wlr_box, interact: bool) void {
	const mapped: bool = switch (self.surface) {
		.xdg => |surf| surf.surface.*.mapped,
		.xwayland => |surf| surf.surface.*.mapped
	};
	if (self.mon == null or !mapped) return;

	const bbox: *const c.wlr_box = if (interact) &ctx.screen_geom else &self.mon.?.window;

	self.setBounds(geom.width, geom.height);
	self.geom = geom;
	self.applyBounds(bbox);

	// TODO REARRANGE
	c.wlr_scene_node_set_position(&self.scene.node, self.geom.x, self.geom.y);
	c.wlr_scene_node_set_position(&self.scene_surface.node, self.bw, self.bw);
	c.wlr_scene_rect_set_size(self.border[0], self.geom.width, self.bw);
	c.wlr_scene_rect_set_size(self.border[1], self.geom.width, self.bw);
	c.wlr_scene_rect_set_size(self.border[2], self.bw, self.geom.height - 2 * self.bw);
	c.wlr_scene_rect_set_size(self.border[3], self.bw, self.geom.height - 2 * self.bw);
	c.wlr_scene_node_set_position(&self.border[1].node, 0, self.geom.height - self.bw);
	c.wlr_scene_node_set_position(&self.border[2].node, 0, self.bw);
	c.wlr_scene_node_set_position(&self.border[3].node, self.geom.width - self.bw, self.bw);

	self.resize_to = self.setSize(
		self.geom.width - 2 * self.bw,
		self.geom.height - 2 * self.bw
	);

	var clip: c.wlr_box = self.getClip();
	c.wlr_scene_subsurface_tree_set_clip(&self.scene_surface.node, &clip);
}

fn applyBounds(self: *const Self, bbox: *const c.wlr_box) void {
	self.geom.width = @max(1 + 2 * self.bw, self.geom.width);
	self.geom.height = @max(1 + 2 * self.bw, self.geom.height);

	if (self.geom.x >= bbox.x + bbox.width)
		self.geom.x = bbox.x + bbox.width - self.geom.width;
	if (self.geom.y >= bbox.y + bbox.height)
		self.geom.y = bbox.y + bbox.height - self.geom.height;
	if (self.geom.x + self.geom.width <= bbox.x)
		self.geom.x = bbox.x;
	if (self.geom.y + self.geom.height <= bbox.y)
		self.geom.y = bbox.y;
}

fn setBorderColor(self: *const Self, color: [4]f32) void {
	inline for (0..4) |i| c.wlr_scene_rect_set_color(self.border[i], color);
}

fn setSize(self: *const Self, w: u32, h: u32) u32 {
	if (config.xwayland and self.surface == .xwayland) {
		c.wlr_xwayland_surface_configure(
			self.surface.xwayland,
			self.geom.x + self.bw, self.geom.y + self.bw,
			w, h
		);
		return 0;
	}
	if (w == self.surface.xdg.unnamed_0.toplevel.*.current.width and
		h == self.surface.xdg.unnamed_0.toplevel.*.current.height) return 0;
	return c.wlr_xdg_toplevel_set_size(self.surface.xdg.unnamed_0.toplevel, w, h);
}
