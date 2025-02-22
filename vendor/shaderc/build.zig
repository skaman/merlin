const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("libshaderc", .{});

    const lib = b.addStaticLibrary(.{
        .name = "libshaderc",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibCpp();
    lib.addIncludePath(b.path("upstream/libshaderc/include/"));
    lib.addIncludePath(b.path("upstream/libshaderc_util/include/"));

    const src_dir = "upstream/";
    lib.addCSourceFiles(.{
        .files = &.{
            src_dir ++ "libshaderc/src/shaderc.cc",
            src_dir ++ "libshaderc_util/src/args.cc",
            src_dir ++ "libshaderc_util/src/compiler.cc",
            src_dir ++ "libshaderc_util/src/file_finder.cc",
            src_dir ++ "libshaderc_util/src/io_shaderc.cc",
            src_dir ++ "libshaderc_util/src/message.cc",
            src_dir ++ "libshaderc_util/src/resources.cc",
            src_dir ++ "libshaderc_util/src/shader_stage.cc",
            src_dir ++ "libshaderc_util/src/spirv_tools_wrapper.cc",
            src_dir ++ "libshaderc_util/src/version_profile.cc",
        },
        .flags = &.{"-DENABLE_HLSL"},
    });

    const glslang = b.dependency("glslang", .{});
    lib.linkLibrary(glslang.artifact("glslang"));

    lib.addIncludePath(b.path("../glslang/upstream/"));
    lib.addIncludePath(b.path("../spirv-headers/upstream/include"));

    b.installArtifact(lib);
}
