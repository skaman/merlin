const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb = b.dependency("stb", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_image_mod = b.addModule("merlin_image", .{
        .root_source_file = b.path("src/image.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_image = b.addLibrary(.{
        .name = "merlin_image",
        .root_module = merlin_image_mod,
    });
    b.installArtifact(merlin_image);

    merlin_image.linkLibrary(stb.artifact("stb"));
    merlin_image.addIncludePath(b.path("../vendor/stb/upstream"));
}
