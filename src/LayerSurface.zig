const c = @import("c.zig").c;

const Client = @import("Client.zig");
const Monitor = @import("Monitor.zig");
const Self = @This();

kind: Client.Type = .layer_shell,
monitor: *Monitor,
scene: *c.wlr_scene_tree,
popups: *c.wlr_scene_tree,
scene_layer: *c.wlr_scene_layer_surface_v1,
link: c.wl_list,
mapped: bool,
layer_surface: *c.wlr_layer_surface_v1,
destroy: c.wl_listener,
unmap: c.wl_listener,
surface_commit: c.wl_listener
