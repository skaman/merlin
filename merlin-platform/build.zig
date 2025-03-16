const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });
    const glfw = b.dependency("glfw", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_platform_mod = b.addModule("merlin_platform", .{
        .root_source_file = b.path("src/platform.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_platform = b.addLibrary(.{
        .name = "merlin_platform",
        .root_module = merlin_platform_mod,
    });
    b.installArtifact(merlin_platform);

    merlin_platform.root_module.addImport("merlin_utils", merlin_utils.module("merlin_utils"));

    merlin_platform.linkLibrary(glfw.artifact("glfw"));
    merlin_platform.addIncludePath(b.path("../vendor/glfw/upstream/include"));

    switch (builtin.target.os.tag) {
        .windows => {
            merlin_platform_mod.addCMacro("GLFW_EXPOSE_NATIVE_WIN32", "");
        },
        .linux => {
            merlin_platform_mod.addCMacro("GLFW_EXPOSE_NATIVE_X11", "");
            merlin_platform_mod.addCMacro("GLFW_EXPOSE_NATIVE_WAYLAND", "");
        },
        .macos => {
            merlin_platform_mod.addCMacro("GLFW_EXPOSE_NATIVE_COCOA", "");
        },
        else => @compileError("Unsupported OS"),
    }
}
