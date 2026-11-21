const c = @import("c");
const ctx = @import("globals.zig");
const list_iterator = @import("list_iterator.zig");

const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");

pub fn print() void {
	var occ: u32 = undefined;
	var urg: u32 = undefined;

	var it = list_iterator.iterate(Monitor, "link", &ctx.monitors);
	while (it.next()) |mon| {
		_ = mon;
		occ = 0;
		urg = 0;
	}

	// TODO NOW
}
