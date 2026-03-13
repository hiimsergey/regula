const config = @import("config");
const std = @import("std");
const linux = std.os.linux;
const c = @import("c.zig").c;
const ctx = @import("globals.zig");
const userconfig = @import("userconfig.zig");

const Client = @import("Client.zig");
const LayerSurface = @import("LayerSurface.zig");
const Monitor = @import("Monitor.zig");

const gpu_reset = c.wl_listener{ .notify = gpuReset };
const layout_change = c.wl_listener{ .notify = updateMonitors };
const new_output = c.wl_listener{ .notify = createMonitor };
const new_xdg_popup = c.wl_listener{ .notify = createPopup };
const new_xdg_toplevel = c.wl_listener{ .notify = createNotify };
const new_layer_surface = c.wl_listener{ .notify = createLayerSurface };
const output_power_mgr_set_mode = c.wl_listener{ .notify = powerMgrSetMode };
const request_activate = c.wl_listener{ .notify = urgent };

// TODO CONSIDER USE in ctx.deinit()
fn cleanup() void {
	cleanupListeners();
	if (config.xwayland) {
		c.wlr_xwayland_destroy(ctx.xwayland);
		ctx.xwayland = null;
	}

	c.wl_display_destroy_clients(ctx.display);
	if (ctx.child_pid > 0) {
		var idc: u32 = undefined;
		linux.kill(-ctx.child_pid, linux.SIG.TERM);
		linux.waitpid(ctx.child_pid, &idc, 0);
	}
	c.wlr_xcursor_manager_destroy(ctx.cursor_mgr);

	c.destroyKeyboardGroup(&ctx.kb_group.destroyFn, null);

	// If it's not destroyed manually, it will cause a use-after-free of wlr_seat.
	// Destroy it until it's fixed on the wlroots side.
	c.wlr_backend_destroy(ctx.backend);

	c.wl_display_destroy(dpy);
	// Destroy after the wayland display (when the monitors are already destroyed)
	// to avoid destroying them with an invalid scene output.
	c.wlr_scene_node_destroy(&ctx.scene.tree.node);
}

fn cleanupMonitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn commitLayerSurfaceNotify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn createLayerSurface(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const layer_surface: *const c.wlr_layer_surface_v1 = @ptrCast(data);
	const surface: *const c.wlr_surface = layer_surface.surface;
	const scene_layer: *const c.wlr_scene_tree =
		ctx.layers[ctx.layer_map[layer_surface.pending.layer]];

	if (layer_surface == null) {
		layer_surface.output = if (ctx.sel_monitor) |sm| sm.output else null;
		if (layer_surface.output == null) {
			c.wlr_layer_surface_v1_destroy(layer_surface);
			return;
		}
	}

	layer_surface.data = ctx.gpa.alloc(LayerSurface, 1)
		catch ctx.die("Failed to allocate memory!", .{});
	var ls: *LayerSurface = layer_surface.data;
	ls.kind = .layer_shell;

	ctx.listenWrapper(&surface.events.commit, &ls.surface_commit, commitLayerSurfaceNotify);
	ctx.listenWrapper(&surface.events.unmap, &ls.unmap, unmapLayerSurfaceNotify);
	ctx.listenWrapper(&layer_surface.events.destroy, &ls.destroy, destroyLayerSurfaceNotify);

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

fn createMonitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const output: *c.wlr_output = @ptrCast(data);

	if (!c.wlr_output_init_render(output, ctx.alloc, ctx.renderer)) return;

	var mon: *Monitor = ctx.gpa.alloc(Monitor, 1)
		catch ctx.die("Failed to allocate memory!", .{});
	output.data = mon;
	mon.output = output;

	for (mon.layers) |*layer| c.wl_list_init(layer);

	var state: c.wlr_output_state = undefined;
	c.wlr_output_state_init(&state);

	@memset(mon.tagset[0..2], 1);

	for (userconfig.MONRULES) |monrule| {
		if (monrule.name != null and
			!std.mem.containsAtLeast(u8, output.name, 1, monrule.name.?))
				continue;

		mon.monitor.x = monrule.x;
		mon.monitor.y = monrule.y;
		mon.mfact = monrule.mfact;
		mon.n_master = monrule.n_master;
		mon.layout[0] = monrule.layout;
		mon.layout[1] = &userconfig.LAYOUTS[
			@intFromBool(userconfig.LAYOUTS.len > 1 and
				monrule.layout != &userconfig.LAYOUTS[1])
		];
		@memcpy(mon.ltsymbol, mon.layout[mon.sellt].symbol[0..mon.ltsymbol.len]);
		c.wlr_output_state_set_scale(&state, monrule.scale);
		c.wlr_output_state_set_transform(&state, monrule.rr);
		break;
	}

	c.wlr_output_state_set_mode(&state, c.wlr_output_preferred_mode(output));

	ctx.listenWrapper(&output.events.frame, &mon.frame, renderMonitor);
	ctx.listenWrapper(&output.events.destroy, &mon.destroy, cleanupMonitor);
	ctx.listenWrapper(&output.events.request_state, &mon.request_state, requestMonitorState);

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

fn createNotify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn createPopup(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn destroyLayerSurfaceNotify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn gpuReset(_: ?*c.wl_listener, _: ?*anyopaque) void {
	const old_renderer = renderer;
	const old_alloc = alloc;
	defer {
		c.wlr_allocator_destroy(old_alloc);
		c.wlr_renderer_destroy(old_renderer);
	}

	renderer = c.wlr_renderer_autocreate(backend) orelse
		ctx.die("wlroots: Failed to create renderer!", .{});
	alloc = c.wlr_allocator_autocreate(backend, renderer) orelse
		ctx.die("wlroots: Failed to create allocator!", .{});

	c.wl_list_remove(&gpu_reset.link);
	c.wl_signal_add(&renderer.events.lost, &gpu_reset);

	c.wlr_compositor_set_renderer(compositor, renderer);

	var m: *Monitor = undefined;
	m = c.wl_container_of(monitors.next, m, "link");
	while (&m.link != &monitors) : (m = c.wl_container_of(m.link.next, m, "link"))
		c.wlr_output_init_render(m.output, alloc, renderer);
}

fn powerMgrSetMode(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.wlr_output_power_v1_set_mode_event = @ptrCast(data);
	const state: c.wlr_output_state = undefined;
	@memset(state, 0);

	const mon: *Monitor = event.output.*.data orelse return;
	mon.gamma_lut_changed = 1;

	c.wlr_output_state_set_enabled(&state, event.mode);
	c.wlr_output_commit_state(mon.output, &state);

	mon.asleep = !event.mode;
	updateMonitors(null, null);
}

fn renderMonitor(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn requestMonitorState(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn unmapLayerSurfaceNotify(_: ?*c.wl_listener, data: ?*anyopaque) void {
	// TODO
}

fn updateMonitors(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const config: *c.wlr_output_configuration_v1 =
		c.wlr_output_configuration_v1_create().?;
	var config_head: *c.wlr_output_configuration_head_v1 = undefined;

	var m: *Monitor = undefined;
	m = // TODO
	// TODO HERE two wl_list_for_each macros
	
	// Now that we update the output layout, we can get its box.
	c.wlr_output_layout_get_box(ctx.output_layout, null, &ctx.screen_geom);

	c.wlr_scene_node_set_position(&ctx.root_bg.node,
		ctx.screen_geom.x, ctx.screen_geom.y);
	c.wlr_scene_rect_set_size(ctx.root_bg,
		ctx.screen_geom.width, ctx.screen_geom.height);

	// Ensures the clients are hidden when regula is locked.
	c.wlr_scene_node_set_position(&ctx.locked_bg.node,
		ctx.screen_geom.x, ctx.screen_geom.y);

	// TODO wl_list_for_each

	if (ctx.sel_monitor != null and ctx.sel_monitor.?.output.enabled) {
		const selmon = ctx.sel_monitor.?;
		// TODO wl_list_for_each
		focusClient(focusTop(selmon), 1);
		if (selmon.lock_surface) {
			Client.notifyEnter(selmon.lock_surface,
				c.wlr_seat_get_keyboard(ctx.seat));
			Client.activeSurface(selmon.lock_surface.surface, 1);
		}
	}

	// TODO FOREIGN figure out why the cursor image is at 0,0 after turning all
	// the monitors on.
	// Move the cursor image where it used to be. It does not generate a
	// wl_pointer.motion event for the clients, it's only the image what it's
	// at the wrong position after all.
	c.wlr_cursor_move(ctx.cursor, null, 0, 0);

	c.wlr_output_manager_v1_set_configuration(ctx.output_mgr, config);
}

fn urgent(_: ?*c.wl_listener, data: ?*anyopaque) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event = @ptrCast(data.?);
	const client: ?*Client = null;
	_ = Client.toplevelFromWlrSurface(event.surface, &client, null);
	if (client == null or c == ctx.sel_monitor.?.topmost_client()) return;

	client.is_urgent = true;

	if (switch (client.?.surface) {
		.xdg => |surf| surf.surface.*.mapped,
		.xwayland => |surf| surf.surface.*.mapped
	}) client.setBorderColor(userconfig.urgent_color);
}
