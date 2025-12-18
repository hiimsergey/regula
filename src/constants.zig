const std = @import("std");

const c = @import("c.zig").c;
const ctx = @import("globals.zig");

const Client = @import("Client.zig");
const Layout = @import("Layout.zig");
const Monitor = @import("Monitor.zig");

pub const HELP =
	\\RegulaWM - an extensible Wayland compositor with sane defaults
	\\
	\\CLI flags:
	\\    -h, --help                 print this message and quit
	\\    -s, --startup <cmd ...>    run the following args as an initial command
	\\    -v, --version              print version and quit
;

pub const FULLSCREEN_BG = [_]f32{0.1, 0.1, 0.1, 1.0};

pub const LAYOUTS = [_]Layout{
	.{ .symbol = "[]=", .arrange = arrange.tile    },
	.{ .symbol = "><>", .arrange = null            },
	.{ .symbol = "[M]", .arrange = arrange.monocle },
};

pub const MONRULES = [_]Monitor.Rule{
	.{
		.name = null,
		.mfact = 0.55,
		.n_master = 1,
		.scale = 1,
		.layout = &LAYOUTS[0],
		.rr = c.WL_OUTPUT_TRANSFORM_NORMAL,
		.x = -1, .y = -1
	}
};

pub const VERSION = "0.0.0";

pub const arrange = struct {
	fn monocle(mon: *const Monitor) void {
		var cl: *const Client = undefined;
		cl = c.wl_container_of(ctx.clients.next, cl, "link");
		while (&cl.link != &ctx.clients) : (cl = c.wl_container_of(cl.link.next, cl, "link")) {
			if (!cl.visible_on(mon) or cl.is_floating or c.is_fullscreen) continue;
			cl.resize(mon.w, false);
		}

		cl = mon.topmost_client() orelse return;
		c.wlr_scene_node_raise_to_top(&cl.scene.node);
	}

	fn tile(mon: *const Monitor) void {
		var cl: *Client = undefined;

		var n: usize = 0;
		cl = c.wl_container_of(ctx.clients.next, cl, "link");
		while (&cl.link != &ctx.clients) : (cl = c.wl_container_of(cl.link.next, cl, "link")) {
			if (cl.visible_on(mon) and !cl.is_floating and !c.is_fullscreen) n += 1;
		}
		if (n == 0) return;

		const mw: u32 = switch (n > mon.n_master) {
			true => if (mon.n_master > 0) @round(mon.window.width * mon.mfact) else 0,
			false => mon.window.width
		};

		var i: u32 = 0;
		var my: u32 = 0;
		var ty: u32 = 0;
		cl = c.wl_container_of(ctx.clients.next, cl, "link");
		while (&cl.link != &ctx.clients) : ({
			cl = c.wl_container_of(cl.link.next, cl, "link");
			i += 1;
		}) {
			if (!cl.visible_on(mon) or cl.is_floating or cl.is_fullscreen) continue;
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

// TODO TEMPORARY before making a proper config framework
pub const config = struct {
	// TODO CONSIDER REWRITE

	/// Default background color formatted as 0xRRGGBBAA
	pub const rootcolor = color(0x22_22_22_ff);

	pub const urgentcolor = (0xff_00_00_ff);
};

fn color(hex: comptime_int) [4]f32 {
	std.debug.assert(hex >= 0 and hex <= 0xff_ff_ff_ff);
	return .{
		(hex >> 24) & 0xff / 255,
		(hex >> 16) & 0xff / 255,
		(hex >> 8) & 0xff / 255,
		(hex & 0xff) / 255,
	};
}
