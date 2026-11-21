// TODO either turn this into a proper config file or distribute constants across other files

const c = @import("c");
const std = @import("std");
const ctx = @import("globals.zig");

const Monitor = @import("Monitor.zig");

/// Cursor size in pixels
pub const cursor_size = 24;
/// Background color
pub const fullscreen_bg = color(0x18_18_18_ff);
/// Background color
pub const root_color = color(0x22_22_22_ff);
/// Border color for regulard windows
pub const border_color = color(0x44_44_44_ff);
/// Border color for focused windows
pub const focus_color = color(0x00_55_77_ff);
/// Border color for urgent windows
pub const urgent_color = color(0xff_00_00_ff);
/// Border pixel of windows
pub const border_pixel: u32 = 1;

/// Keyboard configuration
pub const xkb_rules = c.xkb_rule_names{
	.layout = "lavrent,ru",
	.variant = ",phonetic",
	.options = "grp:alt_caps_toggle,caps:swapescape"
};

/// TODO COMMENT + CONSIDER MOVE
pub const repeat_rate: u32 = 50;

/// TODO COMMENT + CONSIDER MOVE
pub const repeat_delay: u32 = 200;

// TODO COMMENT
fn color(comptime hex: u32) [4]f32 {
	return .{
		(hex >> 24) & 0xff / 255,
		(hex >> 16) & 0xff / 255,
		(hex >> 8) & 0xff / 255,
		(hex & 0xff) / 255,
	};
}
