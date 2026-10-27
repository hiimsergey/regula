const config = @import("config");
const std = @import("std");
const linux = std.os.linux;
const c = @import("c.zig").c;
const ctx = @import("globals.zig");
const lsrs = @import("listeners.zig");
const userconfig = @import("userconfig.zig");

const StructField = std.builtin.Type.StructField;
const Client = @import("Client.zig");
const LayerSurface = @import("LayerSurface.zig");
const Layout = @import("Layout.zig");
const Monitor = @import("Monitor.zig");

const ListenerList: type = T: {
	const field_names: [list.kvs.len][]const u8 = list.keys();

	const attr = StructField.Attributes{
		.default_value_ptr = null,
		.@"align" = @alignOf(c.wl_listener),
		.@"comptime" = true
	};

	break :T @Struct(.auto, null, field_names, @splat(c.wl_listener), @splat(attr));
};

pub const items: ListenerList = items: {
	var result: ListenerList = undefined;
	for (@typeInfo(ListenerList).@"struct".fields) |field| {
		const lsr = c.wl_listener{ .notify = list.get(field.name).? };
		@field(result, field.name) = lsr;
	}
	break :items result;
};

const list = std.StaticStringMap(c.wl_notify_func_t).initComptime(.{
	.{ "cursor_axis",               &axisNotify              },
	.{ "cursor_button",             &buttonPress             },
	.{ "cursor_frame",              &cursorFrame             },
	.{ "cursor_motion",             &motionRelative          },
	.{ "cursor_motion_absolute",    &motionAbsolute          },
	.{ "gpu_reset",                 &gpuReset                },
	.{ "layout_change",             &updateMonitors          },
	.{ "new_idle_inhibitor",        &createIdleInhibitor     },
	.{ "new_input_device",          &inputDevice             },
	.{ "new_layer_surface",         &createLayerSurface      },
	.{ "new_output",                &createMonitor           },
	.{ "new_pointer_constraint",    &createPointerConstraint },
	.{ "new_session_lock",          &lockSession             },
	.{ "new_virtual_keyboard",      &virtualKeyboard         },
	.{ "new_virtual_pointer",       &virtualPointer          },
	.{ "new_xdg_decoration",        &createDecoration        },
	.{ "new_xdg_popup",             &createPopup             },
	.{ "new_xdg_toplevel",          &createNotify            },
	.{ "output_mgr_apply",          &outputMgrApply          },
	.{ "output_mgr_test",           &outputMgrTest           },
	.{ "output_power_mgr_set_mode", &powerMgrSetMode         },
	.{ "request_activate",          &urgent                  },
	.{ "request_cursor",            &setCursor               },
	.{ "request_set_cursor_shape",  &setCursorShape          },
	.{ "request_set_psel",          &setPSel                 }, // TODO RENAME
	.{ "request_set_sel",           &setSel                  }, // TODO RENAME
	.{ "request_start_drag",        &requestStartDrag        },
	.{ "start_drag",                &startDrag               }
} ++ if (config.xwayland) .{
	"new_xwayland_surface",    &createNotifyX11,
	"xwayland_ready",          &xwaylandReady
} else .{});

pub fn deinit() void {
	for (@typeInfo(ListenerList).@"struct".fields) |field| {
		const lsr: c.wl_listener = &@field(items, field.name);
		c.wl_list_remove(&lsr.link);
	}
	if (config.xwayland) {
		c.wl_list_remove(&items.new_xwayland_surface.link);
		c.wl_list_remove(&items.xwayland_ready.link);
	}
}

fn cleanupMonitor(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn commitLayerSurfaceNotify(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn destroyLayerSurfaceNotify(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn renderMonitor(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn requestMonitorState(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn unmapLayerSurfaceNotify(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

// TODO FINAL CHECK proper sorting

fn axisNotify(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn buttonPress(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn cursorFrame(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

pub fn keypress(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

pub fn keypressMod(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

pub fn keyRepeat(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn motionRelative(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn motionAbsolute(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn gpuReset(_: ?*c.wl_listener, _: ?*anyopaque) void {
	const old_renderer = ctx.renderer;
	const old_alloc = ctx.alloc;
	defer {
		c.wlr_allocator_destroy(old_alloc);
		c.wlr_renderer_destroy(old_renderer);
	}

	ctx.renderer = c.wlr_renderer_autocreate(ctx.backend)
		orelse ctx.die("wlroots: Failed to create renderer!", .{}, 1);
	ctx.alloc = c.wlr_allocator_autocreate(ctx.backend, ctx.renderer)
		orelse ctx.die("wlroots: Failed to create allocator!", .{}, 1);

	c.wl_list_remove(&items.gpu_reset.link);
	c.wl_signal_add(&ctx.renderer.events.lost, &items.gpu_reset);

	c.wlr_compositor_set_renderer(ctx.compositor, ctx.renderer);

	var m: *Monitor = undefined;
	m = c.wl_container_of(ctx.monitors.next, m, "link");
	while (&m.link != &ctx.monitors) : (m = c.wl_container_of(m.link.next, m, "link"))
		c.wlr_output_init_render(m.output, ctx.alloc, ctx.renderer);
}

fn updateMonitors(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const output_config: *c.wlr_output_configuration_v1 =
		c.wlr_output_configuration_v1_create().?;
	const config_head: *c.wlr_output_configuration_head_v1 = undefined; // TODO make var
	_ = config_head; // TODO
	_ = data ; // TODO

	const m: *Monitor = undefined; // TODO make var
	_ = m;
	// TODO NOW
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
		const selmon: *const Monitor = ctx.sel_monitor.?;
		// TODO wl_list_for_each
		selmon.topmostClient().?.focus(1);

		if (selmon.lock_surface) |locksurf| {
			Client.notifyEnter(locksurf.surface, c.wlr_seat_get_keyboard(ctx.seat));
			Client.activateSurface(locksurf.surface, true);
		}
	}

	// TODO FOREIGN figure out why the cursor image is at 0,0 after turning all
	// the monitors on.
	// Move the cursor image where it used to be. It does not generate a
	// wl_pointer.motion event for the clients, it's only the image what it's
	// at the wrong position after all.
	c.wlr_cursor_move(ctx.cursor, null, 0, 0);

	c.wlr_output_manager_v1_set_configuration(ctx.output_mgr, output_config);
}

fn createIdleInhibitor(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn inputDevice(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

// TODO CONSIDER MOVE
fn createLayerSurface(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const layer_surface: *c.wlr_layer_surface_v1 = @alignCast(@ptrCast(data));
	const surface: *c.wlr_surface = layer_surface.surface;
	const scene_layer: [*c]c.wlr_scene_tree =
		@ptrCast(ctx.layers[ctx.Layer.map[layer_surface.pending.layer]]);

	if (layer_surface.output == null) {
		layer_surface.output = if (ctx.sel_monitor) |sm| sm.output else null;
		if (layer_surface.output == null) {
			c.wlr_layer_surface_v1_destroy(layer_surface);
			return;
		}
	}

	layer_surface.data = ctx.gpa.create(LayerSurface)
		// TODO CONSIDER outsourcing this error message
		catch ctx.die("Failed to allocate memory!", .{}, 12);
	var ls: *LayerSurface = @alignCast(@ptrCast(layer_surface.data));
	ls.kind = .layer_shell;

	ctx.listenWrapper(&surface.events.commit, &ls.surface_commit, commitLayerSurfaceNotify);
	ctx.listenWrapper(&surface.events.unmap, &ls.unmap, unmapLayerSurfaceNotify);
	ctx.listenWrapper(&layer_surface.events.destroy, &ls.destroy, destroyLayerSurfaceNotify);

	ls.layer_surface = layer_surface;
	ls.monitor = @alignCast(@ptrCast(layer_surface.output.*.data));
	ls.scene_layer = c.wlr_scene_layer_surface_v1_create(scene_layer, layer_surface);
	ls.scene = ls.scene_layer.tree;

	surface.data = c.wlr_scene_tree_create(
		if (layer_surface.current.layer < c.ZWLR_LAYER_SHELL_V1_LAYER_TOP)
			ctx.layers[@backingInt(ctx.Layer.top)]
		else scene_layer
	);
	ls.popups = @alignCast(@ptrCast(surface.data.?));
	ls.popups.node.data = ls;
	ls.scene.node.data = ls;

	c.wl_list_insert(&ls.monitor.layers[layer_surface.pending.layer], &ls.link);
	c.wlr_surface_send_enter(surface, layer_surface.output);
}

fn createMonitor(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const output: *c.wlr_output = @alignCast(@ptrCast(data));

	if (!c.wlr_output_init_render(output, ctx.alloc, ctx.renderer)) return;

	var mon: *Monitor = ctx.gpa.create(Monitor)
		catch ctx.die("Failed to allocate memory!", .{}, 12);
	output.data = mon;
	mon.output = output;

	for (&mon.layers) |*layer| c.wl_list_init(layer);

	var state: c.wlr_output_state = undefined;
	c.wlr_output_state_init(&state);

	@memset(mon.tagset[0..2], 1);

	for (&Monitor.rules) |rule| {
		if (rule.name != null and
			!std.mem.containsAtLeast(u8, std.mem.span(output.name), 1, rule.name.?))
				continue;

		mon.monitor.x = rule.x;
		mon.monitor.y = rule.y;
		mon.mfact = rule.mfact;
		mon.master_n = rule.master_n;
		mon.layout[0] = rule.layout;
		mon.layout[1] = &Layout.layouts[
			@intFromBool(Layout.layouts.len > 1 and
				rule.layout != &Layout.layouts[1])
		];
		@memcpy(&mon.ltsymbol, mon.layout[mon.sellt].symbol[0..mon.ltsymbol.len]);
		c.wlr_output_state_set_scale(&state, rule.scale);
		c.wlr_output_state_set_transform(&state, rule.rr);
		break;
	}

	c.wlr_output_state_set_mode(&state, c.wlr_output_preferred_mode(output));

	ctx.listenWrapper(&output.events.frame, &mon.frame, renderMonitor);
	ctx.listenWrapper(&output.events.destroy, &mon.destroy, cleanupMonitor);
	ctx.listenWrapper(&output.events.request_state, &mon.request_state, requestMonitorState);

	c.wlr_output_state_set_enabled(&state, true);
	_ = c.wlr_output_commit_state(output, &state);
	c.wlr_output_state_finish(&state);

	// TODO CONSIDER REPLACE wl_list with ArrayList
	c.wl_list_insert(&ctx.monitors, &mon.link);

	mon.fullscreen_bg = c.wlr_scene_rect_create(
		ctx.layers[@backingInt(ctx.Layer.fs)],
		0, 0,
		ctx.FULLSCREEN_BG
	);
	c.wlr_scene_node_set_enabled(&mon.fullscreen_bg.node, 0);

	mon.scene_output = c.wlr_scene_output_create(ctx.scene, output);
	if (mon.monitor.x == -1 and mon.monitor.y == -1)
		c.wlr_output_layout_add_auto(ctx.output_layout, output)
	else
		c.wlr_output_layout_add(ctx.output_layout, output, mon.monitor.x, mon.monitor.y);
}

fn createPointerConstraint(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn lockSession(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn virtualKeyboard(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn virtualPointer(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const event: *const c.wlr_virtual_pointer_v1_new_pointer_event = @ptrCast(data.?);
	const device: *const c.wlr_input_device = &event.new_pointer.*.pointer.base;

	c.wlr_cursor_attach_input_device(ctx.cursor, device);
	if (event.suggested_output)
		c.wlr_cursor_map_input_to_output(ctx.cursor, device, event.suggested_output);
}

fn createDecoration(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn createPopup(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn createNotify(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const toplevel: *const c.wlr_xdg_toplevel = @ptrCast(data.?);
	const T = @TypeOf(toplevel.base.data); // TODO hardcode instead
	toplevel.base.data = ctx.gpa.create(T)
		catch ctx.die("Failed to allocate memory!", .{});
	const cl: *Client = toplevel.base.data;
	cl.surface.xdg = toplevel.base;
	cl.bw = ctx.borderpx;

	ctx.listenWrapper(&toplevel.base.surface.events.commit, &cl.commit_lsr,     lsrs.items.commitNotify);
	ctx.listenWrapper(&toplevel.base.surface.events.map,    &cl.map_lsr,        lsrs.items.mapNotify);
	ctx.listenWrapper(&toplevel.base.surface.events.unmap,  &cl.unmap_lsr,      lsrs.items.unmapNotify);
	ctx.listenWrapper(&toplevel.events.destroy,             &cl.destroy_lsr,    lsrs.items.destroyNotify);
	ctx.listenWrapper(&toplevel.events.request_fullscreen,  &cl.fullscreen_lsr, lsrs.items.fullscreenNotify);
	ctx.listenWrapper(&toplevel.events.request_maximize,    &cl.maximize_lsr,   lsrs.items.maximizeNotify);
	ctx.listenWrapper(&toplevel.events.set_title,           &cl.set_title_lsr,  lsrs.items.updateTitle);
}

fn outputMgrApply(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn outputMgrTest(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn powerMgrSetMode(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const event: *c.wlr_output_power_v1_set_mode_event = @alignCast(@ptrCast(data));
	const mon: *Monitor = if (event.output.*.data) |ptr| @alignCast(@ptrCast(ptr)) else
		return;
	mon.gamma_lut_changed = 1;

	var state = c.wlr_output_state{};
	c.wlr_output_state_set_enabled(@ptrCast(&state), event.mode != 0);
	_ = c.wlr_output_commit_state(mon.output, &state);

	mon.asleep = @intFromBool(event.mode == 0);
	updateMonitors(null, null);
}

fn urgent(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	const event: *c.wlr_xdg_activation_v1_request_activate_event =
		@alignCast(@ptrCast(data));
	const client: ?*const Client = null;
	_ = Client.toplevelFromWlrSurface(event.surface, @constCast(@ptrCast(&client)), null);
	if (client == null or c == ctx.sel_monitor.?.topmostClient()) return;

	client.is_urgent = true;

	if (switch (client.?.surface) {
		.xdg => |surf| surf.surface.*.mapped,
		.xwayland => |surf| surf.surface.*.mapped
	}) client.setBorderColor(userconfig.urgent_color);
}

fn setCursor(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn setCursorShape(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn setPSel(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn setSel(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn requestStartDrag(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn startDrag(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn createNotifyX11(_: ?[*]c.wl_listener, data: ?*anyopaque) callconv(.c) void {
	// TODO
	_ = data;
}

fn xwaylandReady(_: ?[*]c.wl_listener, _: ?*anyopaque) callconv(.c) void {
	c.wlr_xwayland_set_seat(ctx.xwayland, ctx.seat);
	const xcursor: *const c.wlr_xcursor = c.wlr_xcursor_manager_get_xcursor(ctx.cursor_mgr, "default", 1)
		orelse return;

	const img = xcursor.images[0].*;
	c.wlr_xwayland_set_cursor(
		ctx.xwayland,
		img.buffer, img.width * 4,
		img.width, img.height,
		img.hotspot_x, img.hotspot_y);
}
