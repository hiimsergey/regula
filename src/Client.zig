const config = @import("config");
const c = @import("c.zig").c;

const Monitor = @import("Monitor.zig");

pub const Type = enum(i8) {invalid = -1, xdg_shell, layer_shell, x11};

const Self = @This();
kind: Type,
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

fn get_surface(self: *const Self) ?c.struct_wlr_surface {
	if (config.xwayland and self.kind == .x11)
		return self.surface.xwayland.surface;
	return self.surface.xdg.surface;
}

fn set_border_color(self: *const Self, color: [4]f32) void {
	for (0..4) |i| c.wlr_scene_rect_set_color(self.border[i], color);
}

fn visible_on(self: *const Self, mon: ?*const Monitor) bool {
	return mon != null and self.mon == mon and
		@intFromBool(self.tags & mon.?.tagset[mon.?.seltags]);
}
