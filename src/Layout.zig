const Monitor = @import("Monitor.zig");

symbol: []const u8,
arrange: *const fn (*Monitor) void
