const std = @import("std");

const glslang_build = @import("glslang-build.zig");
const spirv_headers_build = @import("spirv-headers-build.zig");
const spirv_tools_build = @import("spirv-tools-build.zig");

pub fn addLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    spirv_tools: *std.Build.Step.Compile,
    glslang: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const libshaderc = b.addStaticLibrary(.{
        .name = "libshaderc",
        .target = target,
        .optimize = optimize,
    });

    libshaderc.linkLibCpp();
    libshaderc.addIncludePath(b.path("vendor/shaderc/libshaderc/include/"));
    libshaderc.addIncludePath(b.path("vendor/shaderc/libshaderc_util/include/"));

    const src_dir = "vendor/shaderc/";
    libshaderc.addCSourceFiles(.{
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

    spirv_headers_build.linkLibrary(b, libshaderc);
    spirv_tools_build.linkLibrary(b, libshaderc, spirv_tools);
    glslang_build.linkLibrary(b, libshaderc, glslang);

    return libshaderc;
}

pub fn linkLibrary(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    libshaderc: *std.Build.Step.Compile,
) void {
    exe.linkLibrary(libshaderc);
    exe.addIncludePath(b.path("vendor/shaderc/libshaderc/include/"));
}
