const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const DebugAllocator = std.heap.DebugAllocator(.{});
/// Comptime wrapper that resolves to the slow but helpful `DebugAllocator` in
/// Debug mode but a user-chosen one in all the other modes
const Self = @This();

dbg_state: if (is_debug) DebugAllocator else void,

const is_debug = builtin.mode == .Debug;

/// Initialize Zig's `DebugAllocator`.
pub fn init() Self {
	return .{ .dbg_state = if (is_debug) DebugAllocator.init else {} };
}

/// Return `DebugAllocator`'s allocator or `alt`, if not in Debug mode.
pub fn allocator(self: *Self, alt: Allocator) Allocator {
	return if (is_debug) self.dbg_state.allocator() else alt;
}

/// Deinit Zig's `DebugAllocator`, if necessary.
pub fn deinit(self: *Self) void {
	if (is_debug) _ = self.dbg_state.deinit();
}
