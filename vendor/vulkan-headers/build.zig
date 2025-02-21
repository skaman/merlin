const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("vulkan_headers", .{});

    const lib = b.addStaticLibrary(.{
        .name = "vulkan_headers",
        .target = target,
        .optimize = optimize,
    });

    lib.addCSourceFiles(.{
        .files = &.{
            "empty.c",
        },
    });

    lib.addIncludePath(b.path("upstream/include"));

    b.installArtifact(lib);
}
