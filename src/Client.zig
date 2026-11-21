// TODO FINAL FIX pub and private fn decls
// TODO FINAL FIX inline and not-inline fn decls

const c = @import("c");
const config = @import("config");
const std = @import("std");
const linux = std.os.linux;
const ctx = @import("globals.zig");
const list_iterator = @import("list_iterator.zig");
const status = @import("status.zig");
const userconfig = @import("userconfig.zig");

const LayerSurface = @import("LayerSurface.zig");
const Monitor = @import("Monitor.zig");
const Self = @This();

// TODO CONSIDER
pub const Kind = enum(i8) {invalid = -1, xdg_shell, layer_shell, x11};

mon: ?*Monitor,
scene: *c.wlr_scene_tree,
border: [4]*c.wlr_scene_rect, // top, bottom, left, right // TODO CONSIDER using enum instead
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
commit_lsr: c.wl_listener,
map_lsr: c.wl_listener,
maximize_lsr: c.wl_listener,
unmap_lsr: c.wl_listener,
destroy_lsr: c.wl_listener,
set_title_lsr: c.wl_listener,
fullscreen_lsr: c.wl_listener,
set_decoration_mode_lsr: c.wl_listener,
destroy_decoration_lsr: c.wl_listener,

bw: c_int,
tags: u32,
// TODO RESEARCH how does this work in zig? is this efficient?
is: packed struct(u8) {
	floating: bool,
	urgent: bool,
	fullscreen: bool,
	_: u5 = 0
},
resize_to: u32,

xwayland: if (config.xwayland) struct {
	activate_lsr: c.wl_listener,
	associate_lsr: c.wl_listener,
	dissociate_lsr: c.wl_listener,
	configure_lsr: c.wl_listener,
	set_hints_lsr: c.wl_listener,
} else void = undefined,

pub fn focus(self: *Self, lift: bool) void {
	focusClient(self, lift);
}

pub fn resetFocus() void {
	focusClient(null, false);
}

pub fn notifyEnter(surf: [*]c.wlr_surface, kb: ?*const c.wlr_keyboard) void {
	if (kb) |k| {
		c.wlr_seat_keyboard_notify_enter(
			ctx.seat,
			surf,
			&k.keycodes, k.num_keycodes, &k.modifiers);
		return;
	}

	c.wlr_seat_keyboard_notify_enter(ctx.seat, surf, null, 0, null);
}

pub fn toplevelFromWlrSurface(
	surf: ?*c.wlr_surface,
	cl_ptr: ?*?*const Self,
	lysurf_ptr: ?**const LayerSurface
) Kind {
	var client_kind = Kind.invalid;
	var client: *Self = undefined;
	var our_ls: *LayerSurface = undefined;

	body: {
		const root_surface: *c.wlr_surface =
			c.wlr_surface_get_root_surface(surf orelse return .invalid);

		if (config.xwayland) {
			const xsurface: ?*c.wlr_xwayland_surface =
				c.wlr_xwayland_surface_try_from_wlr_surface(root_surface);
			if (@intFromPtr(xsurface) != 0) {
				client = @alignCast(@ptrCast(xsurface.?.*.data.?));
				client_kind = switch (client.surface) {
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
			client_kind = .layer_shell;
			break :body;
		}

		var xdg_surface: ?*c.wlr_xdg_surface =
			c.wlr_xdg_surface_try_from_wlr_surface(root_surface);
		while (xdg_surface) |*xdgsurf| {
			var tmp_xdgsurf: *c.wlr_xdg_surface = undefined;
			switch (xdgsurf.*.role) {
				c.WLR_XDG_SURFACE_ROLE_POPUP => {
					if (xdgsurf.*.unnamed_0.popup == null or
						xdgsurf.*.unnamed_0.popup.*.parent == null)
						return .invalid;

					tmp_xdgsurf = c.wlr_xdg_surface_try_from_wlr_surface(
						xdgsurf.*.unnamed_0.popup.*.parent)
					orelse return toplevelFromWlrSurface(
						xdgsurf.*.unnamed_0.popup.*.parent,
						cl_ptr, lysurf_ptr);

					xdgsurf.* = tmp_xdgsurf;
				},
				c.WLR_XDG_SURFACE_ROLE_TOPLEVEL => {
					client = @alignCast(@ptrCast(xdgsurf.*.data));
					client_kind = switch (client.surface) {
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

	if (lysurf_ptr) |pl| pl.* = our_ls;
	if (cl_ptr) |pc| pc.* = client;

	return client_kind;
}

pub fn activateSurface(surf: [*c]c.wlr_surface, activated: bool) void {
	if (config.xwayland) ifc: {
		const xsurface: [*]c.wlr_xwayland_surface =
			c.wlr_xwayland_surface_try_from_wlr_surface(surf) orelse break :ifc;
		c.wlr_xwayland_surface_activate(xsurface, activated);
		return;
	}

	const toplevel: [*]c.wlr_xdg_toplevel =
		c.wlr_xdg_toplevel_try_from_wlr_surface(surf) orelse return;
	_ = c.wlr_xdg_toplevel_set_activated(toplevel, activated); // TODO CONSIDER ERRHANDLE
}

fn setBounds(self: *Self, w: i32, h: i32) u32 {
	if (config.xwayland and self.surface == .xwayland) return 0;

	if (c.wl_resource_get_version(self.surface.xdg.unnamed_0.toplevel.*.resource)
		< c.XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION
		or w < 0
		or h < 0
		or (self.bounds.width == w and self.bounds.height == h))
	{
		return 0;
	}

	self.bounds.width = w;
	self.bounds.height = h;
	return c.wlr_xdg_toplevel_set_bounds(self.surface.xdg.unnamed_0.toplevel, w, h);
}

fn getAppId(self: *const Self) [*]const u8 {
	const broken: [*]const u8 = "broken";
	if (config.xwayland and self.surface == .xwayland)
		return if (self.surface.xwayland.class) |cls| cls else broken;
	return if (self.surface.xdg.unnamed_0.toplevel.*.app_id) |aid| aid else broken;
}

fn getClip(self: *const Self) c.wlr_box {
	var result = c.wlr_box{
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
		if (self.surface.xwayland.parent) |par|
			_ = toplevelFromWlrSurface(par.surface, &result, null);
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
		return if (self.surface.xwayland.title) |tit| tit else broken;
	return if (self.surface.xdg.unnamed_0.toplevel.*.title) |tit| tit else broken;
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

fn isOnMonitor(self: *const Self, mon: *const Monitor) bool {
	// TODO
	_ = self;
	_ = mon;
}

fn isStopped(self: *const Self) bool {
	if (config.xwayland and self.surface == .xwayland) return false;

	var pid: c_int = undefined;
	var info = std.mem.zeroes(linux.siginfo_t);
	const flag = linux.W.NOHANG | linux.W.CONTINUED | linux.W.STOPPED | linux.W.NOWAIT;
	c.wl_client_get_credentials(self.surface.xdg.client, &pid, null, null);
	if (linux.waitpid(linux.P.PID, pid, &info, flag) < 0) {
		// This process is not our child process, while is very unlikely that
		// it is stopped, in order to do not skip frames, assume that it is.
		const errno = std.posix.errno(-1);
		if (errno == .ECHILD) return true;
	}
	else if (info.si_pid and
		(info.si_code == linux.W.STOPPED or info.si_code == linux.W.TRAPPED))
	{
		return true;
	}

	return false;
}

fn isUnmanaged(self: *const Self) bool {
	return if (config.xwayland and self.surface == .xwayland)
		self.surface.xwayland.override_redirect
		else false;
}

pub fn visibleOn(self: *const Self, mon: ?*const Monitor) bool {
	return mon != null
		and self.mon == mon
		and (self.tags & mon.?.tagset[mon.?.seltags]) == 1;
}

pub fn resize(self: *Self, geom: c.wlr_box, interact: bool) void {
	// v TODO CONSIDER optimize
	const mapped: bool = switch (self.surface) {
		.xdg => |surf| surf.surface.*.mapped,
		.xwayland => |surf| surf.surface.*.mapped
	};
	if (self.mon == null or !mapped) return;

	const bbox: *const c.wlr_box = if (interact) &ctx.screen_geom else &self.mon.?.window;

	_ = self.setBounds(geom.width, geom.height);
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

pub fn setFloating(self: *Self, floating: bool) void {
	// TODO
	_ = self;
	_ = floating;
}

pub fn setFullscreen(self: *Self, fullscreen: bool) void {
	// TODO
	_ = self;
	_ = fullscreen;
}

// TODO CONSIDER change datatype of `new_tags`
pub fn setMonitor(self: *Self, mon: ?*Monitor, new_tags: u32) void {
	const old_mon: ?*const Monitor = self.mon;
	if (old_mon == mon) return;

	self.mon = mon;
	self.prev = self.geom;

	if (old_mon) |om| om.arrange();
	if (mon) |m| {
		self.resize(self.geom, false);
		self.tags = if (new_tags != 0) new_tags else m.tagset[m.seltags];
		self.setFullscreen(self.is.fullscreen);
		self.setFloating(self.is.floating);
	}
	ctx.sel_mon.?.topmostClient().?.focus(true);
}

pub fn wantsFocus(self: *const Self) bool {
	if (!config.xwayland) return false;

	return self.isUnmanaged()
		and c.wlr_xwayland_surface_override_redirect_wants_focus(self.surface.xwayland)
		and c.wlr_xwayland_surface_icccm_input_model(self.surface.xwayland)
			!= c.WLR_ICCCM_INPUT_MODEL_NONE;
}

fn applyBounds(self: *Self, bbox: *const c.wlr_box) void {
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
	inline for (0..4) |i| c.wlr_scene_rect_set_color(self.border[i], &color);
}

fn setSize(self: *const Self, w: c_int, h: c_int) u32 {
	if (config.xwayland and self.surface == .xwayland) {
		c.wlr_xwayland_surface_configure(
			self.surface.xwayland,
			@intCast(self.geom.x + self.bw),
			@intCast(self.geom.y + self.bw),
			@intCast(w), @intCast(h));
		return 0;
	}
	if (w == self.surface.xdg.unnamed_0.toplevel.*.current.width and
		h == self.surface.xdg.unnamed_0.toplevel.*.current.height) return 0;
	return c.wlr_xdg_toplevel_set_size(self.surface.xdg.unnamed_0.toplevel, w, h);
}

fn focusClient(maybe_cl: ?*Self, lift: bool) void {
	if (ctx.is_locked) return;

	const old_surf: ?*c.wlr_surface = ctx.seat.keyboard_state.focused_surface;

	if (maybe_cl) |cl| {
		if (lift) c.wlr_scene_node_raise_to_top(&cl.scene.node);

		const surf_ptr: *c.wlr_surface = switch (cl.surface) {
			.xdg => @ptrCast(cl.surface.xdg),
			.xwayland => @ptrCast(cl.surface.xwayland)
		};
		if (surf_ptr == old_surf) return;
	}

	var old_cl: ?*const Self = null;
	var old_lysurf: *const LayerSurface = undefined;
	const old_cl_kind: Kind = toplevelFromWlrSurface(old_surf, &old_cl, &old_lysurf);
	if (old_cl_kind == .xdg_shell) {
		var it = list_iterator.iterate_safe(
			c.wlr_xdg_popup, "link", &old_cl.?.surface.xdg.popups);
		while (it.next()) |popup|
			c.wlr_xdg_popup_destroy(popup);

		// TODO NOW
	}

	blk: {
		const cl: *Self = maybe_cl orelse break :blk;
		if (cl.isUnmanaged()) break :blk;

		c.wl_list_remove(&cl.flink);
		c.wl_list_insert(&ctx.focus_stack, &cl.flink);
		ctx.sel_mon = cl.mon;
		cl.is.urgent = false;

		if (ctx.exclusive_focus == null and ctx.seat.drag == null)
			cl.setBorderColor(userconfig.focus_color);
	}

	blk: {
		const old_surf_unwrapped = old_surf orelse break :blk;
		if (maybe_cl) |cl| {
			const cl_surf: *c.wlr_surface = switch(cl.surface) {
				.xdg => @ptrCast(cl.surface.xdg),
				.xwayland => @ptrCast(cl.surface.xwayland)
			};
			if (cl_surf == old_surf_unwrapped) break :blk;
		}

		const coords: ?usize = null; // TODO PLACEHOLDER REMOVE

		if (old_cl_kind == .layer_shell
			and coords != null
			and &old_lysurf.layer_surface.current.layer >= c.ZWLR_LAYER_SHELL_V1_LAYER_TOP
		) {
			return;
		}
		else if (old_cl != null
			and old_cl.? == @as(*const Self, @alignCast(@ptrCast(ctx.exclusive_focus)))
			and old_cl.?.wantsFocus()
		) {
			return;
		}
		// TODO STYLE
		else blk2: {
			const old_cl_unwrapped = old_cl orelse break :blk2;
			if (old_cl_unwrapped.isUnmanaged()) break :blk2;
			if (maybe_cl) |cl| if (cl.wantsFocus()) break :blk2;

			old_cl_unwrapped.setBorderColor(userconfig.border_color);
			Self.activateSurface(old_surf, false);
		}
	}
	status.print();
}

