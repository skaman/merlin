const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_image = b.dependency("merlin_image", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });
    const cgltf = b.dependency("cgltf", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_gltf_mod = b.addModule("merlin_gltf", .{
        .root_source_file = b.path("src/gltf.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_gltf = b.addLibrary(.{
        .name = "merlin_gltf",
        .root_module = merlin_gltf_mod,
    });
    b.installArtifact(merlin_gltf);

    merlin_gltf.root_module.addImport("merlin_image", merlin_image.module("merlin_image"));
    merlin_gltf.root_module.addImport("merlin_utils", merlin_utils.module("merlin_utils"));

    merlin_gltf.linkLibrary(cgltf.artifact("cgltf"));
    merlin_gltf.addIncludePath(b.path("../vendor/cgltf/upstream"));
}
