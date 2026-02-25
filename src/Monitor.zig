const c = @import("c.zig").c;
const ctx = @import("globals.zig");

const Client = @import("Client.zig");
const Layout = @import("Layout.zig");
const Self = @This();

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
layers: [4]c.wl_list,
layout: [2]*Layout,
seltags: u32,
sellt: u32,
tagset: [2]u32,
mfact: f32,
gamma_lut_changed: i32,
n_master: i32,
ltsymbol: [16]u8,
asleep: i32,

pub const Rule = struct {
	name: ?[]const u8,
	mfact: f32,
	n_master: u32,
	scale: f32,
	layout: *const Layout,
	rr: c.wl_output_transform,
	x: i32,
	y: i32
};

fn topmostClient(self: *Self) ?*Client {
	var cl: *Client = undefined;
	cl = c.wl_container_of(ctx.fstack.next, cl, "flink");
	while (&cl.flink != &ctx.fstack) :
		(cl = c.wl_container_of(cl.flink.next, cl, "flink"))
		if (cl.visibleOn(self)) return cl;
	return null;
}
