const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("spirv_headers", .{});

    const lib = b.addStaticLibrary(.{
        .name = "spirv_headers",
        .target = target,
        .optimize = optimize,
    });

    lib.addCSourceFiles(.{
        .files = &.{
            "empty.c",
        },
    });

    lib.addIncludePath(b.path("upstream/include"));
    lib.addIncludePath(b.path("upstream/include/spirv/unified1/"));

    b.installArtifact(lib);
}
