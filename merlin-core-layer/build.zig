const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw = b.dependency("glfw", .{});
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan_utility_libraries = b.dependency("vulkan_utility_libraries", .{});
    const ktx_software = b.dependency("ktx_software", .{});
    const zmath = b.dependency("zmath", .{});

    const merlin_core_layer_mod = b.addModule("merlin_core_layer", .{
        .root_source_file = b.path("src/mcl.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_core_layer = b.addLibrary(.{
        .name = "merlin_core_layer",
        .root_module = merlin_core_layer_mod,
    });
    b.installArtifact(merlin_core_layer);

    merlin_core_layer.linkLibC();
    merlin_core_layer.linkLibrary(glfw.artifact("glfw"));
    merlin_core_layer.addIncludePath(b.path("../vendor/glfw/upstream/include"));
    merlin_core_layer.linkLibrary(vulkan_headers.artifact("vulkan_headers"));
    merlin_core_layer.addIncludePath(b.path("../vendor/vulkan-headers/upstream/include"));
    merlin_core_layer.linkLibrary(vulkan_utility_libraries.artifact("vulkan_utility_libraries"));
    merlin_core_layer.addIncludePath(b.path("../vendor/vulkan-utility-libraries/upstream/include"));
    merlin_core_layer.linkLibrary(ktx_software.artifact("ktx_software"));
    merlin_core_layer.addIncludePath(b.path("../vendor/ktx-software/upstream/include"));
    merlin_core_layer.root_module.addImport("zmath", zmath.module("root"));

    switch (builtin.target.os.tag) {
        .windows => {
            merlin_core_layer_mod.addCMacro("GLFW_EXPOSE_NATIVE_WIN32", "");
            merlin_core_layer_mod.addCMacro("VK_USE_PLATFORM_WIN32_KHR", "");
        },
        .linux => {
            merlin_core_layer_mod.addCMacro("GLFW_EXPOSE_NATIVE_X11", "");
            merlin_core_layer_mod.addCMacro("GLFW_EXPOSE_NATIVE_WAYLAND", "");
            merlin_core_layer_mod.addCMacro("VK_USE_PLATFORM_XCB_KHR", "");
            merlin_core_layer_mod.addCMacro("VK_USE_PLATFORM_XLIB_KHR", "");
            merlin_core_layer_mod.addCMacro("VK_USE_PLATFORM_WAYLAND_KHR", "");
        },
        .macos => {
            merlin_core_layer_mod.addCMacro("GLFW_EXPOSE_NATIVE_COCOA", "");
            merlin_core_layer_mod.addCMacro("VK_USE_PLATFORM_MACOS_MVK", "");
        },
        else => @compileError("Unsupported OS"),
    }

    const merlin_core_layer_unit_tests = b.addTest(.{
        .root_module = merlin_core_layer_mod,
    });

    const run_merlin_core_layer_unit_tests = b.addRunArtifact(merlin_core_layer_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_merlin_core_layer_unit_tests.step);
}
