const c = @import("c");
const std = @import("std");
const log = std.log;
const ctx = @import("globals.zig");

pub const help_text =
	\\RegulaWM - an extensible Wayland compositor with sane defaults
	\\
	\\Options:
	\\  -h, --help           print this message and quit
	\\  -s, --startup <cmd>  run following args as initial command
	\\  -v, --version        print version and quit
	\\
	\\Exit codes:
	\\   0  success
	\\   1  generic error
	\\  12  out of memory
;

pub const version = "0.0.0";

pub fn main(init: std.process.Init) u8 {
	if (handleArgs(init.minimal.args)) |stat| return stat;

	ctx.init(init) catch return 1;
	defer ctx.deinit();

	if (!init.environ_map.contains("XDG_RUNTIME_DIR")) {
		log.err("Environment variable XDG_RUNTIME_DIR must be set!", .{});
		return 1;
	}

	return 0;
}

/// Returns error code the compositor should exit with or null if it should keep
/// running.
fn handleArgs(args: std.process.Args) ?u8 {
	var it = args.iterate();
	_ = it.skip(); // Skip executable name
	const flag = it.next() orelse return null;

	if (std.mem.eql(u8, flag, "--startup") or std.mem.eql(u8, flag, "-s")) {
		// TODO
		return 0;
	}
	else if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
		log.info(help_text, .{});
		return 0;
	}
	else if (std.mem.eql(u8, flag, "--version") or std.mem.eql(u8, flag, "-v")) {
		log.info(version, .{});
		return 0;
	}

	log.err("Invalid flag '{s}'! See `regula --help` for correct usage!", .{flag});
	return 1;
}

// TODO FINAL ALL move variable declarations as close as possible to their use
