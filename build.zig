const Build = @import("std").Build;

// Latest Zig version as of writing this: 0.15.2
pub fn build(b: *Build) void {
	// Options
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// Executable declaration
	const exe = b.addExecutable(.{
		.name = "regula",
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize
		})
	});

	// Linking libraries
	exe.root_module.link_libc = true;
	exe.root_module.addIncludePath(b.path("include"));
	exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/wlroots-0.19" });
	exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/pixman-1" });
	exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
	exe.root_module.linkSystemLibrary("wlroots-0.19", .{});
	exe.root_module.linkSystemLibrary("wayland-server", .{});
	exe.root_module.linkSystemLibrary("xkbcommon", .{});
	exe.root_module.linkSystemLibrary("input", .{});

	// Run command
	const run_exe = b.addRunArtifact(exe);
	const run_step = b.step("run", "Run the program");
	run_step.dependOn(&run_exe.step);

	// User-defined options
	const xwayland = b.option(
		bool,
		"xwayland", "Compile with XWayland support (default: true)"
	) orelse true;

	const options = b.addOptions();
	options.addOption(bool, "xwayland", xwayland);

	exe.root_module.addOptions("config", options);

	// Actual installation
	b.installArtifact(exe);
}
