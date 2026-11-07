const c = @import("c");
const ctx = @import("globals.zig");
const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");
const Self = @This();

symbol: []const u8,
arrangeFn: ?*const fn (*Monitor) void,

pub const arrange = struct {
	fn monocle(mon: *const Monitor) void {
		// TODO ALL CONSIDER REPLACEWITH iterator
		var cl: *Client = @fieldParentPtr("link", &ctx.clients.next.*);
		while (&cl.link != &ctx.clients) :
			(cl = @fieldParentPtr("link", &cl.link.next.*))
		{
			if (!cl.visibleOn(mon) or cl.is.floating or cl.is.fullscreen) continue;
			cl.resize(mon.window, false);
		}

		cl = mon.topmostClient() orelse return;
		c.wlr_scene_node_raise_to_top(&cl.scene.node);
	}

	fn tile(mon: *const Monitor) void {
		var cl: *Client = @fieldParentPtr("link", &ctx.clients.next.*);
		var n: usize = 0;

		while (&cl.link != &ctx.clients) :
			(cl = @fieldParentPtr("link", &cl.link.next.*))
		{
			if (cl.visibleOn(mon) and !cl.is.floating and !cl.is.fullscreen) n += 1;
		}
		if (n == 0) return;

		const mw: u32 = if (n > mon.master_n)
			if (mon.master_n > 0) @round(mon.window.width * mon.mfact) else 0
			else mon.window.width;

		var i: u32 = 0;
		var my: u32 = 0;
		var ty: u32 = 0;
		cl = @fieldParentPtr("link", &ctx.clients.next.*);
		while (&cl.link != &ctx.clients) : ({
			cl = @fieldParentPtr("link", &cl.link.next.*);
			i += 1;
		}) {
			if (!cl.visibleOn(mon) or cl.is.floating or cl.is.fullscreen) continue;
			if (i < mon.master_n) {
				cl.resize(.{
					.x = mon.window.x,
					.y = mon.window.y,
					.width = mw,
					.height = @divFloor(mon.window.height - my, @min(n, mon.master_n) - i)
				}, false);
				my = cl.geom.height;
			} else {
				cl.resize(.{
					.x = mon.window.x + mw,
					.y = mon.window.y + ty,
					.width = mon.window.width - mw,
					.height = @divFloor(mon.window.height - ty, n - i)
				}, false);
				ty = cl.geom.height;
			}
		}
	}
};

pub const layouts = [_]Self{
	.{ .symbol = "[]=", .arrangeFn = arrange.tile    },
	.{ .symbol = "><>", .arrangeFn = null            },
	.{ .symbol = "[M]", .arrangeFn = arrange.monocle },
};
