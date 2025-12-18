const c = @import("c.zig").c;

const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");

const Self = @This();
kind: Client.Type = .layer_shell,
monitor: *Monitor,
scene: *c.struct_wlr_scene_tree,
popups: *c.struct_wlr_scene_tree,
scene_layer: *c.struct_wlr_scene_layer_surface_v1,
link: c.struct_wl_list,
mapped: bool,
layer_surface: *c.struct_wlr_layer_surface_v1,
destroy: c.struct_wlr_listener,
unmap: c.struct_wlr_listener,
surface_commit: c.struct_wlr_listener
