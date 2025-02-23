const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("spirv_reflect", .{});

    const lib = b.addStaticLibrary(.{
        .name = "spirv_reflect",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibCpp();
    lib.addIncludePath(b.path("upstream"));
    lib.addIncludePath(b.path("upstream/include"));

    const src_dir = "upstream/";
    lib.addCSourceFiles(.{
        .files = &.{
            src_dir ++ "spirv_reflect.c",
        },
    });

    //const spirv_headers = b.dependency("spirv_headers", .{});
    //lib.linkLibrary(spirv_headers.artifact("spirv_headers"));

    //lib.addIncludePath(b.path("../spirv-headers/upstream/include"));
    //lib.addIncludePath(b.path("../spirv-headers/upstream/include/spirv/unified1/"));

    b.installArtifact(lib);
}
