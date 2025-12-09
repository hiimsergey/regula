const config = @import("config");
const c = @import("c.zig").c;

const ctx = @import("globals.zig");

const Monitor = @import("Monitor.zig");

pub const Type = enum(i8) {invalid = -1, xdg_shell, layer_shell, x11};

const Self = @This();
kind: Type,
mon: ?*Monitor,
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
resize_to: u32,

xwayland: if (config.xwayland) struct {
	activate: c.struct_wlr_listener,
	associate: c.struct_wlr_listener,
	dissociate: c.struct_wlr_listener,
	configure: c.struct_wlr_listener,
	set_hints: c.struct_wlr_listener,
} else void,

fn apply_bounds(self: *const Self, bbox: *const c.struct_wlr_box) void {
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

inline fn get_clip(self: *const Self) c.struct_wlr_box {
	var result = self.struct_wlr_box{
		.x = 0, .y = 0,
		.width = self.geom.width - self.bw,
		.height = self.geom.height - self.bw,
	};
	if (config.xwayland and self.kind == .x11) return result;

	result.x = self.surface.xdg.geometry.x;
	result.y = self.surface.xdg.geometry.y;
	return result;
}

fn get_surface(self: *const Self) ?c.struct_wlr_surface {
	if (config.xwayland and self.kind == .x11)
		return self.surface.xwayland.surface;
	return self.surface.xdg.surface;
}

fn resize(self: *const Self, geo: c.struct_wlr_box, interact: bool) void {
	if (self.mon == null or !self.get_surface().?.mapped) return;

	const bbox: *const c.struct_wlr_box = if (interact) &ctx.sgeom else &self.mon.?.window;

	self.set_bounds(geo.width, geo.height);
	self.geom = geo;
	self.apply_bounds(bbox);

	c.wlr_scene_node_set_position(&self.scene.node, self.geom.x, self.geom.y);
	c.wlr_scene_node_set_position(&self.scene_surface.node, self.bw, self.bw);
	c.wlr_scene_rect_set_size(self.border[0], self.geom.width, self.bw);
	c.wlr_scene_rect_set_size(self.border[1], self.geom.width, self.bw);
	c.wlr_scene_rect_set_size(self.border[2], self.bw, self.geom.heihgt - 2 * self.bw);
	c.wlr_scene_rect_set_size(self.border[3], self.bw, self.geom.heihgt - 2 * self.bw);
	c.wlr_scene_node_set_position(&self.border[1].node, 0, self.geom.height - self.bw);
	c.wlr_scene_node_set_position(&self.border[2].node, 0, self.bw);
	c.wlr_scene_node_set_position(&self.border[3].node, self.geom.width - self.bw, self.bw);

	self.resize_to = self.set_size(
		self.geom.width - 2 * self.bw,
		self.geom.height - 2 * self.bw
	);

	var clip: c.struct_wlr_box = self.get_clip();
	// TODO NOtW
}

fn set_border_color(self: *const Self, color: [4]f32) void {
	for (0..4) |i| c.wlr_scene_rect_set_color(self.border[i], color);
}

inline fn set_bounds(self: *const Self, w: i32, h: i32) u32 {
	if (config.xwayland and self.kind == .x11) return 0;

	if (c.wl_resource_get_version(self.surface.xdg.unnamed_0.toplevel.*.resource) <
		c.XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION or w < 0 or h < 0 or
		(self.bounds.width == w and self.bounds.height == h))
		return 0;

	self.bounds.width = w;
	self.bounds.height = h;
	return c.wlr_xdg_toplevel_set_bounds(self.surface.xdg.unnamed_0.toplevel, w, h);
}

inline fn set_size(self: *const Self, w: u32, h: u32) u32 {
	if (config.xwayland and self.kind == .x11) {
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

fn visible_on(self: *const Self, mon: ?*const Monitor) bool {
	return mon != null and self.mon == mon and
		@intFromBool(self.tags & mon.?.tagset[mon.?.seltags]);
}
