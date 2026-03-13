const std = @import("std");
const log = std.log;
const c = @import("c.zig").c;
const ctx = @import("globals.zig");

pub const help_text =
	\\RegulaWM - an extensible Wayland compositor with sane defaults
	\\
	\\Options:
	\\  -h, --help           print this message and quit
	\\  -s, --startup <cmd>  run the following args as an initial command
	\\  -v, --version        print version and quit
	\\
	\\Exit codes:
	\\   0  success
	\\   1  generic error
	\\  12  out of memory
;

pub const version = "0.0.0";

pub fn main() u8 {
	if (handleArgs()) |stat| return stat;

	ctx.init() catch return 1;
	defer ctx.deinit();

	const xdg_runtime_dir_set: bool = std.process.hasEnvVar(ctx.gpa, "XDG_RUNTIME_DIR")
	catch |e| switch (e) {
		error.InvalidWtf8 => unreachable,
		error.OutOfMemory => return 12
	};
	if (!xdg_runtime_dir_set) {
		log.err("Environment variable XDG_RUNTIME_DIR must be set!", .{});
		return 1;
	}

	return 0;
}

/// Returns error code the compositor should exit with or null if it should keep
/// running.
fn handleArgs() ?u8 {
	var args = std.process.args();
	_ = args.skip(); // Skip executable name
	const flag = args.next() orelse return null;

	if (std.mem.eql(u8, flag, "--startup") or std.mem.eql(u8, flag, "-s")) {
		// TODO
		return 0;
	}
	else if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
		stdoutPrint(help_text);
		return 0;
	}
	else if (std.mem.eql(u8, flag, "--version") or std.mem.eql(u8, flag, "-v")) {
		stdoutPrint(version);
		return 0;
	}

	log.err("Invalid flag '{s}'! See `regula --help` for correct usage!", .{flag});
	return 1;
}

/// Single unbuffered print through stdout without formatting arguments
fn stdoutPrint(comptime msg: []const u8) void {
	const stdout_wrapper = std.fs.File.stdout().writer(&.{});
	stdout_wrapper.interface.print(msg, .{}) catch {};
}
