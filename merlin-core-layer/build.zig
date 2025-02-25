const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw = b.dependency("glfw", .{});
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan_utility_libraries = b.dependency("vulkan_utility_libraries", .{});
    const zmath = b.dependency("zmath", .{});

    const merlin_core_layer_mod = b.addModule("merlin_core_layer", .{
        .root_source_file = b.path("src/mcl.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_core_layer = b.addSharedLibrary(.{
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
    merlin_core_layer.root_module.addImport("zmath", zmath.module("root"));
}
