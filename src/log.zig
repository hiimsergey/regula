const std = @import("std");

var stdout_buf: [512]u8 = undefined;
var stderr_buf: [512]u8 = undefined;

var stdout = std.fs.File.stdout().writer(&stdout_buf);
var stderr = std.fs.File.stderr().writer(&stderr_buf);

pub fn println(comptime fmt: []const u8, args: anytype) void {
	stdout.interface.print(fmt ++ "\n", args) catch {};
}
pub fn errln(comptime fmt: []const u8, args: anytype) void {
	stderr.interface.print("error: " ++ fmt ++ "\n", args) catch {};
}

pub fn flush_stdout() void {
	stdout.interface.flush() catch {};
}
pub fn flush_stderr() void {
	stderr.interface.flush() catch {};
}
