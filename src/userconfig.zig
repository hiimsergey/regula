// TODO either turn this into a proper config file or distribute constants across other files

const std = @import("std");
const c = @import("c.zig").c;
const ctx = @import("globals.zig");

const Monitor = @import("Monitor.zig");

pub const fullscreen_bg = color(0x18_18_18_ff);

/// Default background color
pub const root_color = color(0x22_22_22_ff);

/// Defaut border color for urgent windows
pub const urgent_color = color(0xff_00_00_ff);

fn color(comptime hex: u32) [4]f32 {
	return .{
		(hex >> 24) & 0xff / 255,
		(hex >> 16) & 0xff / 255,
		(hex >> 8) & 0xff / 255,
		(hex & 0xff) / 255,
	};
}
