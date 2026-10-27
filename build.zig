const Build = @import("std").Build;

// Latest Zig version as of writing this: 0.17.0
pub fn build(b: *Build) void {
	// Options
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	const translate_c = b.addTranslateC(.{
		.root_source_file = b.path("src/c.h"),
		.target = target,
		.optimize = optimize
	});
	// TODO NOW NOW figure out how to do the "if (config.xwayland)" part in
	// c.zig

	// Linking libraries
	translate_c.linkSystemLibrary("wlroots-0.19", .{});
	translate_c.linkSystemLibrary("wayland-server", .{});
	translate_c.linkSystemLibrary("xkbcommon", .{});
	translate_c.linkSystemLibrary("input", .{});
	// XWayland
	translate_c.linkSystemLibrary("xcb", .{});
	translate_c.linkSystemLibrary("xcb-icccm", .{});

	translate_c.addIncludePath(b.path("include"));
	translate_c.addIncludePath(.{ .cwd_relative = "/usr/include/wlroots-0.19" });
	translate_c.addIncludePath(.{ .cwd_relative = "/usr/include/pixman-1" });
	translate_c.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });

	// Executable declaration
	const exe = b.addExecutable(.{
		.name = "regula",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{
				.{
					.name = "c",
					.module = translate_c.createModule()
				}
			}
		})
	});

	// User-defined options
	const xwayland = b.option(
		bool,
		"xwayland", "Compile with XWayland support (default: true)"
	) orelse true;

	const options = b.addOptions();
	options.addOption(bool, "xwayland", xwayland);

	exe.root_module.addOptions("config", options);

	// Run command
	const run_exe = b.addRunArtifact(exe);
	const run_step = b.step("run", "Run the program");
	run_step.dependOn(&run_exe.step);

	// Actual installation
	b.installArtifact(exe);
}
