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

fn cleanup_monitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn commit_layer_surface_notify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn create_layer_surface(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const layer_surface: *const c.struct_wlr_layer_surface_v1 = @ptrCast(data);
	const surface: *const c.struct_wlr_surface = layer_surface.surface;
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

	ctx.listen_wrapper(&surface.events.commit, &ls.surface_commit, commit_layer_surface_notify);
	ctx.listen_wrapper(&surface.events.unmap, &ls.unmap, unmap_layer_surface_notify);
	ctx.listen_wrapper(&layer_surface.events.destroy, &ls.destroy, destroy_layer_surface_notify);

	ls.layer_surface = layer_surface;
	ls.monitor = layer_surface.output.*.data;
	ls.scene_layer = c.wlr_scene_layer_surface_v1_create(scene_layer, layer_surface);
	ls.scene = ls.scene_layer.tree;

	surface.data = c.wlr_scene_tree_create(
		if (layer_surface.current.layer < c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)
			ctx.layers[@intFromEnum(ctx.Layer.top)]
		else scene_layer
	);
	ls.popups = surface.data;
	ls.popups.node.data = ls;
	ls.scene.node.data = ls;

	c.wl_list_insert(&ls.monitor.layers[layer_surface.pending.layer], &ls.link);
	c.wlr_surface_send_enter(surface, layer_surface.output);
}
fn create_monitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const output: *c.struct_wlr_output = @ptrCast(data);

	if (!c.wlr_output_init_render(output, ctx.alloc, ctx.renderer)) return;

	var mon: *Monitor = ctx.gpa.alloc(Monitor, 1) catch ctx.die("Failed to allocate memory!", .{});
	output.data = mon;
	mon.output = output;

	for (mon.layers) |*layer| c.wl_list_init(layer);

	var state: c.wlr_output_state = undefined;
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
		mon.layout[1] = &constants.LAYOUTS[
			@intFromBool(constants.LAYOUTS.len > 1 and monrule.layout != &constants.LAYOUTS[1])
		];
		@memcpy(mon.ltsymbol, mon.layout[mon.sellt].symbol[0..mon.ltsymbol.len]);
		c.wlr_output_state_set_scale(&state, monrule.scale);
		c.wlr_output_state_set_transform(&state, monrule.rr);
		break;
	}

	c.wlr_output_state_set_mode(&state, c.wlr_output_preferred_mode(output));

	ctx.listen_wrapper(&output.events.frame, &mon.frame, render_monitor);
	ctx.listen_wrapper(&output.events.destroy, &mon.destroy, cleanup_monitor);
	ctx.listen_wrapper(&output.events.request_state, &mon.request_state, request_monitor_state);

	c.wlr_output_state_set_enabled(&state, 1);
	c.wlr_output_commit_state(output, &state);
	c.wlr_output_state_finish(&state);

	// TODO CONSIDER REPLACE wl_list with ArrayList
	c.wl_list_insert(&mons, &mon.link);

	mon.fullscreen_bg = c.wlr_scene_rect_create(
		ctx.layers[@intFromEnum(ctx.Layer.fs)],
		0, 0,
		ctx.FULLSCREEN_BG
	);
	c.wlr_scene_node_set_enabled(&mon.fullscreen_bg.node, 0);

	mon.scene_output = c.wlr_scene_output_create(ctx.scene, output);
	if (mon.monitor.x == -1 and mon.monitor.y == -1)
		c.wlr_output_layout_add_auto(ctx.output_layout, outputA)
	else
		c.wlr_output_layout_add(ctx.output_layout, output, mon.monitor.x, mon.monitor.y);
}
fn create_notify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn create_popup(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn destroy_layer_surface_notify(_: ?*c.wl_listener, data: ?*anyopaque) void {
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
fn render_monitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn request_monitor_state(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}
fn unmap_layer_surface_notify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
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
