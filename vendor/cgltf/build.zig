const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("cgltf", .{});

    const lib = b.addStaticLibrary(.{
        .name = "cgltf",
        .target = target,
        .optimize = optimize,
    });

    lib.addCSourceFiles(.{
        .files = &.{
            "impl.c",
        },
        .flags = &.{
            // "-std=c99",
            // "-fno-sanitize=undefined",
        },
    });
    lib.linkLibC();

    lib.addIncludePath(b.path("upstream"));

    b.installArtifact(lib);
}
