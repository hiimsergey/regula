const c = @import("c");
const ctx = @import("globals.zig");
const list_iterator = @import("list_iterator.zig");
const status = @import("status.zig");

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
lock_surface: ?*c.wlr_session_lock_surface_v1,
monitor: c.wlr_box,
window: c.wlr_box,
layers: [4]c.wl_list,
layout: [2]*const Layout,
seltags: u32,
sellt: u32,
tagset: [2]u32,
mfact: f32,
gamma_lut_changed: i32,
// TODO FINAL ALL CHECK consistent naming convention
master_n: u32,
ltsymbol: [16]u8,
asleep: i32,

pub const Rule = struct {
	name: ?[]const u8,
	mfact: f32,
	master_n: u32,
	scale: f32,
	layout: *const Layout,
	rr: c.wl_output_transform,
	x: i32,
	y: i32
};

pub const rules = [_]Rule{
	.{
		.name = null,
		.mfact = 0.55,
		.master_n = 1,
		.scale = 1,
		.layout = &Layout.layouts[0],
		.rr = c.WL_OUTPUT_TRANSFORM_NORMAL,
		.x = -1, .y = -1
	}
};

pub fn close(self: *Self) void {
	const mon_n: usize = @intCast(c.wl_list_length(&ctx.monitors));
	if (mon_n == 0) {
		ctx.sel_mon = null;
	} else if (self == ctx.sel_mon) {
		const mons_next: *c.wl_list = @ptrCast(ctx.monitors.next);
		for (0..mon_n) |_| {
			ctx.sel_mon = @fieldParentPtr("link", mons_next);
			if (ctx.sel_mon.?.output.enabled) break;
		}

		if (!ctx.sel_mon.?.output.enabled) ctx.sel_mon = null;
	}

	var it = list_iterator.iterate(Client, "link", &ctx.clients);
	while (it.next()) |cl| {
		if (cl.is.floating and cl.geom.x > self.monitor.width) {
			const geom = c.wlr_box{
				.x = cl.geom.x - self.window.width,
				.y = cl.geom.y,
				.width = cl.geom.width,
				.height = cl.geom.height
			};
			cl.resize(geom, false);
		}
		if (cl.mon == self) cl.setMonitor(ctx.sel_mon, cl.tags);
	}

	ctx.sel_mon.?.topmostClient().?.focus(true);
	status.print();
}

pub fn arrange(self: Self) void {
	_ = self;
	// TODO
}

pub fn fromXY(x: f64, y: f64) ?*Self {
	const output: *c.wlr_output = c.wlr_output_layout_output_at(ctx.output_layout, x, y) orelse return null;
	return output.data;
}

pub fn topmostClient(self: *const Self) ?*Client {
	var fstack_it = list_iterator.iterate(Client, "flink", &ctx.focus_stack);
	while (fstack_it.next()) |cl|
		if (cl.visibleOn(self)) return cl;

	return null;
}
