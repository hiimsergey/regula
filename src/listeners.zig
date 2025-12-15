const std = @import("std");

const c = @import("c.zig").c;
const constants = @import("constants.zig");
const ctx = @import("globals.zig");

const LayerSurface = @import("LayerSurface.zig");
const Monitor = @import("Monitor.zig");

const gpu_reset = c.struct_wl_listener{ .notify = gpu_reset };
const layout_change = c.struct_wl_listener{ .notify = update_monitors };
const new_output = c.struct_wl_listener{ .notify = create_monitor };
const new_xdg_popup = c.struct_wl_listener{ .notify = create_popup };
const new_xdg_toplevel = c.struct_wl_listener{ .notify = create_notify };
const new_layer_surface = c.struct_wl_listener{ .notify = create_layer_surface };
const output_power_mgr_set_mode = c.struct_wl_listener{ .notify = power_mgr_set_mode };
const request_activate = c.struct_wl_listener{ .notify = urgent };

fn create_layer_surface(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const layer_surface: *const c.struct_wlr_layer_surface_v1 = @ptrCast(data);
	const sur: *const c.struct_wlr_surface = layer_surface.surface;
	const scene_layer: *const c.struct_wlr_scene_tree =
		ctx.layers[ctx.layer_map[layer_surface.pending.layer]];

	if (layer_surface == null) {
		layer_surface.output = if (ctx.selmon) |sm| sm.output else null;
		if (layer_surface.output == null) {
			c.wlr_layer_surface_v1_destroy(layer_surface);
			return;
		}
	}

	layer_surface.data = ctx.gpa.alloc(LayerSurface, 1) catch ctx.die("Failed to allocate memory!", .{});
	var ls: *LayerSurface = layer_surface.data;
	ls.kind = .layer_shell;

	ls.surface_commit.notify = commit_layer_surface_notify;
	c.wl_signal_add(&sur.events.commit, ls.surface_commit.notify, &ls.surface_commit);

	// TODO
}
fn create_monitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const output: *c.struct_wlr_output = @ptrCast(data);

	if (!c.wlr_output_init_render(output, ctx.alloc, ctx.renderer)) return;

	var mon: *Monitor = ctx.gpa.alloc(Monitor, 1) catch ctx.die("Failed to allocate memory!", .{});
	output.data = mon;
	mon.output = output;

	for (mon.layers) |*layer| c.wl_list_init(layer);

	c.wlr_output_state_init(&state);

	@memset(mon.tagset[0..2], 1);

	for (constants.MONRULES) |monrule| {
		if (monrule.name != null and
			!std.mem.containsAtLeast(u8, output.name, 1, monrule.name.?)) continue;

		mon.monitor.x = monrule.x;
		mon.monitor.y = monrule.y;
		mon.mfact = monrule.mfact;
		mon.n_master = monrule.n_master;
		mon.layout[0] = monrule.layout;
		mon.layout[1] = lay
		@memcpy(mon.ltsymbol, mon.layout[mon.sellt].symbol[0..mon.ltsymbol.len]);
		c.wlr_output_state_set_scale(&state, monrule.scale);
		c.wlr_output_state_set_transform(&state, monrule.rr);
		break;
	}

	// TODO NOW
}
fn create_notify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn create_popup(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn gpu_reset(_: ?*c.struct_wl_listener, _: ?*anyopaque) void {
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
fn power_mgr_set_mode(_: ?*c.wl_listener, data: ?*anyopaque) void {
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
fn update_monitors(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const config: *c.struct_wlr_output_configuration_v1 =
		c.wlr_output_configuration_v1_create();
	var config_head: *c.struct_wlr_output_configuration_head_v1 = undefined;

	var m: *Monitor = undefined;
	m = // TODO
}
fn urgent(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(data.?);
	const client: ?*Client = null;
	toplevel_from_wlr_surface(event.surface, &client, null);
	if (client == null or c == selmon.topmost_client()) return;

	client.is_urgent = true;

	if (client.get_surface().mapped)
		client.set_border_color(constants.config.urgentcolor);
}
