const c = @import("c.zig").c;
const ctx = @import("globals.zig");
const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");
const Self = @This();

symbol: []const u8,
arrangeFn: ?*const fn (*Monitor) void,

pub const arrange = struct {
	fn monocle(mon: *const Monitor) void {
		// TODO ALL CONSIDER REPLACEWITH iterator
		var cl: *const Client = undefined;
		cl = c.wl_container_of(ctx.clients.next, cl, "link");
		while (&cl.link != &ctx.clients) :
			(cl = c.wl_container_of(cl.link.next, cl, "link"))
		{
			if (!cl.visibleOn(mon) or cl.is_floating or c.is_fullscreen) continue;
			cl.resize(mon.w, false);
		}

		cl = mon.topmostClient() orelse return;
		c.wlr_scene_node_raise_to_top(&cl.scene.node);
	}

	fn tile(mon: *const Monitor) void {
		var cl: *Client = undefined;

		var n: usize = 0;
		cl = c.wl_container_of(ctx.clients.next, cl, "link");
		while (&cl.link != &ctx.clients) :
			(cl = c.wl_container_of(cl.link.next, cl, "link"))
		{
			if (cl.visibleOn(mon) and !cl.is_floating and !c.is_fullscreen) n += 1;
		}
		if (n == 0) return;

		const mw: u32 = if (n > mon.n_master)
			if (mon.n_master > 0) @round(mon.window.width * mon.mfact) else 0
			else mon.window.width;

		var i: u32 = 0;
		var my: u32 = 0;
		var ty: u32 = 0;
		cl = c.wl_container_of(ctx.clients.next, cl, "link");
		while (&cl.link != &ctx.clients) : ({
			cl = c.wl_container_of(cl.link.next, cl, "link");
			i += 1;
		}) {
			if (!cl.visibleOn(mon) or cl.is_floating or cl.is_fullscreen) continue;
			if (i < mon.n_master) {
				cl.resize(.{
					.x = mon.window.x,
					.y = mon.window.y,
					.width = mw,
					.height = @divFloor(mon.window.height - my, @min(n, mon.n_master) - i)
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
	.{ .symbol = "[]=", .arrange = arrange.tile    },
	.{ .symbol = "><>", .arrange = null            },
	.{ .symbol = "[M]", .arrange = arrange.monocle },
};
