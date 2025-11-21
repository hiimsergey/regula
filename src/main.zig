const c = @import("c.zig").c;
const std = @import("std");
const linux = std.os.linux;

const constants = @import("constants.zig");
const log = @import("log.zig");

const AllocatorWrapper = @import("allocator.zig").AllocatorWrapper;

const Layer = enum(u8) {
	background,
	bottom,
	tile,
	float,
	top,
	fs,
	overlay,
	block
};
const NUM_LAYERS = @typeInfo(Layer).@"enum".fields.len;

const Context = struct {
	display: *c.struct_wl_display,
	event_loop: *c.struct_wl_event_loop,
	backend: *c.struct_wlr_backend,
	session: *c.struct_wlr_session,
	scene: *c.struct_wlr_scene,
	root_bg: *c.struct_wlr_scene_rect,
	layers: [NUM_LAYERS]*c.struct_wlr_scene_tree,
	drag_icon: *c.struct_wlr_scene_tree,

	fn init() !Context {
		var res: Context = undefined;
		res.display = c.wl_display_create() orelse return error.Generic;
		res.event_loop = c.wl_display_get_event_loop(ctx.display) orelse return error.Generic;
		
		res.backend = c.wlr_backend_autocreate(res.event_loop, @ptrCast(&res.session));
		if (@intFromPtr(res.backend) == 0) {
			log.errln("wlroots: Failed to create backend!", .{});
			return error.Generic;
		}

		res.scene = c.wlr_scene_create();

		const bg: [4]f32 = color(constants.config.rootcolor);
		res.root_bg = c.wlr_scene_rect_create(&res.scene.tree, 0, 0, &bg);

		for (&res.layers) |*layer| layer.* = c.wlr_scene_tree_create(&res.scene.tree);
		res.drag_icon = c.wlr_scene_tree_create(&res.scene.tree);
		c.wlr_scene_node_place_below(
			&res.drag_icon.node,
			&res.layers[@intFromEnum(Layer.block)].node
		);

		// TODO 2476

		return res;
	}
};
var ctx: Context = undefined;

pub fn main() u8 {
	var aw = AllocatorWrapper.init();
	defer aw.deinit();
	const gpa = aw.allocator();

	defer {
		log.flush_stderr();
		log.flush_stdout();
	}

	const stat = handle_args();
	if (stat) |s| return s;

	if (!(std.process.hasEnvVar(gpa, "XDG_RUNTIME_DIR") catch {
		log.errln("Failed to check if the envvar XDG_RUNTIME_DIR is set!", .{});
		return 1;
	})) {
		log.errln("The envvar XDG_RUNTIME_DIR is not set!", .{});
		return 1;
	}

	setup() catch return 1;
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

fn setup() !void {
	// Reset signal handlers for SIGCHLD, SIGINT, SIGTERM and SIGPIPE
	const sa = linux.Sigaction{
		.flags = linux.SA.RESTART,
		.handler = .{ .handler = handlesig },
		.mask = undefined
	};
	_ = linux.sigemptyset();

	inline for ([_]comptime_int{
		linux.SIG.CHLD,
		linux.SIG.INT,
		linux.SIG.TERM,
		linux.SIG.PIPE,
	}) |sig| _ = linux.sigaction(sig, &sa, null);

	c.wlr_log_init(c.WLR_ERROR, null);

	ctx = try Context.init();
}

fn handlesig(signo: i32) callconv(.c) void {
	var idc: u32 = undefined;
	if (signo == linux.SIG.CHLD)
		while (linux.waitpid(-1, &idc, linux.W.NOHANG) > 0) {} // TODO oh god
	else if (signo == linux.SIG.INT or signo == linux.SIG.TERM)
		c.wl_display_terminate(ctx.display);
}

fn color(hex: comptime_int) [4]f32 {
	return .{
		(hex >> 24) & 0xff / 255,
		(hex >> 16) & 0xff / 255,
		(hex >> 8) & 0xff / 255,
		(hex & 0xff) / 255,
	};
}
