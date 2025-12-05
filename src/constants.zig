const std = @import("std");

pub const HELP =
	\\RegulaWM - an extensible Wayland compositor with sane defaults
	\\
	\\CLI flags:
	\\    -h, --help                 print this message and quit
	\\    -s, --startup <cmd ...>    run the following args as an initial command
	\\    -v, --version              print version and quit
;

pub const VERSION = "0.0.0";

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
