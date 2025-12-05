const std = @import("std");

const c = @import("c.zig").c;
const constants = @import("constants.zig");
const log = @import("log.zig");
const ctx = @import("globals.zig");

const Generic = error.Generic;

pub fn main() u8 {
	ctx.init_allocator();

	defer {
		log.flush_stderr();
		log.flush_stdout();
	}

	const stat = handle_args();
	if (stat) |s| return s;

	if (!(std.process.hasEnvVar(ctx.gpa, "XDG_RUNTIME_DIR") catch {
		log.errln("Failed to check if the envvar XDG_RUNTIME_DIR is set!", .{});
		return 1;
	})) {
		log.errln("The envvar XDG_RUNTIME_DIR is not set!", .{});
		return 1;
	}

	ctx.init() catch return 1;
	defer ctx.deinit();

	return 0;
}

/// Returns the error code the compositor should exit with or `null` if it should keep
/// running.
fn handle_args() ?u8 {
	var args = std.process.args();
	_ = args.skip(); // Skip executable name
	const flag = args.next() orelse return null;

	if (std.mem.eql(u8, flag, "--startup") or std.mem.eql(u8, flag, "-s")) {} // TODO
	else if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
		log.println(constants.HELP, .{});
		return 0;
	} else if (std.mem.eql(u8, flag, "--version") or std.mem.eql(u8, flag, "-v")) {
		log.println(constants.VERSION, .{});
		return 0;
	}

	log.errln("invalid flag '{s}'! Use '--help' to see available flags!", .{flag});
	return 1;
}
