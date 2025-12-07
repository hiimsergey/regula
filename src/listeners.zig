const c = @import("c.zig").c;
const constants = @import("constants.zig");
const ctx = @import("globals.zig");

const Monitor = @import("Monitor.zig");

const gpu_reset = c.struct_wl_listener{ .notify = gpu_reset };
const layout_change = c.struct_wl_listener{ .notify = update_monitors };
const new_output = c.struct_wl_listener{ .notify = create_monitor };
const new_xdg_popup = c.struct_wl_listener{ .notify = create_popup };
const new_xdg_toplevel = c.struct_wl_listener{ .notify = create_notify };
const output_power_mgr_set_mode = c.struct_wl_listener{ .notify = power_mgr_set_mode };
const request_activate = c.struct_wl_listener{ .notify = urgent };

pub fn create_monitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const output: *c.struct_wlr_output = @ptrCast(data);

	if (!c.wlr_output_init_render(output, ctx.alloc, ctx.renderer)) return;

	var mon: *Monitor = ctx.gpa.alloc(Monitor, 1) catch die("Failed to allocate memory!", .{});
	output.data = mon;
	mon.output = output;

	for (mon.layers) |*layer| c.wl_list_init(layer);

	c.wlr_output_state_init(&state);

	@memset(mon.tagset[0..2], 1);

	for (constants.MONRULES) |monrule| {
		// TODO NOW
	}
}
pub fn create_notify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
pub fn create_popup(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
pub fn gpu_reset(_: ?*c.struct_wl_listener, _: ?*anyopaque) void {
	const old_renderer, const old_alloc = .{ renderer, alloc };
	defer {
		c.wlr_allocator_destroy(old_alloc);
		c.wlr_renderer_destroy(old_renderer);
	}

	renderer = c.wlr_renderer_autocreate(backend) orelse {
		log.errln("wlroots: Failed to create renderer!", .{});
		return Generic;
	};

	alloc = c.wlr_allocator_autocreate(backend, renderer) orelse {
		log.errln("wlroots: Failed to create allocator!", .{});
		return Generic;
	};

	c.wl_list_remove(&gpu_reset.link);
	c.wl_signal_add(&renderer.events.lost, &gpu_reset);

	c.wlr_compositor_set_renderer(compositor, renderer);

	var m: *Monitor = undefined;
	m = c.wl_container_of(monitors.next, m, "link");
	while (&m.link != &monitors) : (m = c.wl_container_of(m.link.next, m, "link"))
		c.wlr_output_init_render(m.output, alloc, renderer);
}
pub fn power_mgr_set_mode(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.struct_wlr_output_power_v1_set_mode_event = @ptrCast(data);
	const state: c.wlr_output_state = undefined;
	@memset(state, 0);

	const mon: *Monitor = event.output.*.data orelse return;
	mon.gamma_lut_changed = 1;

	c.wlr_output_state_set_enabled(&state, event.mode);
	c.wlr_output_commit_state(mon.output, &state);

	mon.asleep = !event.mode;
	update_monitors(null, null);
}
pub fn update_monitors(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const config: *c.struct_wlr_output_configuration_v1 =
		c.wlr_output_configuration_v1_create();
	var config_head: *c.struct_wlr_output_configuration_head_v1 = undefined;

	var m: *Monitor = undefined;
	m = // TODO
}
pub fn urgent(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(data.?);
	const client: ?*Client = null;
	toplevel_from_wlr_surface(event.surface, &client, null);
	if (client == null or c == selmon.topmost_client()) return;

	client.is_urgent = true;

	if (client.get_surface().mapped)
		client.set_border_color(constants.config.urgentcolor);
}
