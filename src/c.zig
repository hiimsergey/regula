const config = @import("config");

pub const c = @cImport({
	@cDefine("WLR_USE_UNSTABLE", {});
	@cDefine("_POSIX_C_SOURCE", "200809L");

	@cInclude("libinput.h");
	@cInclude("linux/input-event-codes.h");
	@cInclude("wayland-server-core.h");
	@cInclude("wlr/backend.h");
	@cInclude("wlr/backend/libinput.h");
	@cInclude("wlr/render/allocator.h");
	@cInclude("wlr/render/wlr_renderer.h");
	@cInclude("wlr/types/wlr_alpha_modifier_v1.h");
	@cInclude("wlr/types/wlr_compositor.h");
	@cInclude("wlr/types/wlr_cursor.h");
	@cInclude("wlr/types/wlr_cursor_shape_v1.h");
	@cInclude("wlr/types/wlr_data_control_v1.h");
	@cInclude("wlr/types/wlr_data_device.h");
	@cInclude("wlr/types/wlr_drm.h");
	@cInclude("wlr/types/wlr_export_dmabuf_v1.h");
	@cInclude("wlr/types/wlr_fractional_scale_v1.h");
	@cInclude("wlr/types/wlr_gamma_control_v1.h");
	@cInclude("wlr/types/wlr_idle_inhibit_v1.h");
	@cInclude("wlr/types/wlr_idle_notify_v1.h");
	@cInclude("wlr/types/wlr_input_device.h");
	@cInclude("wlr/types/wlr_keyboard.h");
	@cInclude("wlr/types/wlr_keyboard_group.h");
	@cInclude("wlr/types/wlr_layer_shell_v1.h");
	@cInclude("wlr/types/wlr_linux_dmabuf_v1.h");
	@cInclude("wlr/types/wlr_linux_drm_syncobj_v1.h");
	@cInclude("wlr/types/wlr_output.h");
	@cInclude("wlr/types/wlr_output_layout.h");
	@cInclude("wlr/types/wlr_output_management_v1.h");
	@cInclude("wlr/types/wlr_output_power_management_v1.h");
	@cInclude("wlr/types/wlr_pointer.h");
	@cInclude("wlr/types/wlr_pointer_constraints_v1.h");
	@cInclude("wlr/types/wlr_presentation_time.h");
	@cInclude("wlr/types/wlr_primary_selection.h");
	@cInclude("wlr/types/wlr_primary_selection_v1.h");
	@cInclude("wlr/types/wlr_relative_pointer_v1.h");
	@cInclude("wlr/types/wlr_scene.h");
	@cInclude("wlr/types/wlr_screencopy_v1.h");
	@cInclude("wlr/types/wlr_seat.h");
	@cInclude("wlr/types/wlr_server_decoration.h");
	@cInclude("wlr/types/wlr_session_lock_v1.h");
	@cInclude("wlr/types/wlr_single_pixel_buffer_v1.h");
	@cInclude("wlr/types/wlr_subcompositor.h");
	@cInclude("wlr/types/wlr_viewporter.h");
	@cInclude("wlr/types/wlr_virtual_keyboard_v1.h");
	@cInclude("wlr/types/wlr_virtual_pointer_v1.h");
	@cInclude("wlr/types/wlr_xcursor_manager.h");
	@cInclude("wlr/types/wlr_xdg_activation_v1.h");
	@cInclude("wlr/types/wlr_xdg_decoration_v1.h");
	@cInclude("wlr/types/wlr_xdg_output_v1.h");
	@cInclude("wlr/types/wlr_xdg_shell.h");
	@cInclude("wlr/util/log.h");
	@cInclude("wlr/util/region.h");
	@cInclude("xkbcommon/xkbcommon.h");

	if (config.xwayland) {
		@cInclude("wlr/xwayland.h");
		@cInclude("xcb/xcb.h");
		@cInclude("xcb/xcb_icccm.h");
	}
});

