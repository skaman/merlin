const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_image = b.dependency("merlin_image", .{
        .target = target,
        .optimize = optimize,
    });

    const ktx_software = b.dependency("ktx_software", .{
        .target = target,
        .optimize = optimize,
    });
    const vulkan_headers = b.dependency("vulkan_headers", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_ktx_mod = b.addModule("merlin_ktx", .{
        .root_source_file = b.path("src/ktx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_ktx = b.addLibrary(.{
        .name = "merlin_ktx",
        .root_module = merlin_ktx_mod,
    });
    b.installArtifact(merlin_ktx);

    merlin_ktx.root_module.addImport("merlin_image", merlin_image.module("merlin_image"));

    merlin_ktx.linkLibrary(ktx_software.artifact("ktx_software"));
    merlin_ktx.addIncludePath(b.path("../vendor/ktx-software/upstream/include"));

    merlin_ktx.linkLibrary(vulkan_headers.artifact("vulkan_headers"));
    merlin_ktx.addIncludePath(b.path("../vendor/vulkan-headers/upstream/include"));
}
