//! Comptime wrapper that resolves to the slow but helpful `DebugAllocator` in
//! Debug mode but a user-chosen one in all the other modes.

const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const DebugAllocator = std.heap.DebugAllocator(.{});
const Self = @This();

dbg_state: if (is_debug) DebugAllocator else void,

const is_debug = builtin.mode == .Debug;

/// Initialize Zig's `DebugAllocator`.
pub fn init() Self {
	return if (is_debug) .{ .dbg_state = DebugAllocator.init } else .{ .dbg_state = {} };
}

/// Return the `DebugAllocator`'s allocator.
pub fn allocator(self: *Self, alt: Allocator) Allocator {
	return if (is_debug) self.dbg_state.allocator() else alt;
}

/// Deinit Zig's `DebugAllocator` and log an error message if
/// the program contains Zig-side memory leaks.
pub fn deinit(self: *Self) void {
	if (is_debug and self.dbg_state.deinit() == .leak) @panic("Leaks found!");
}
