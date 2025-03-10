const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("ktx_software", .{});

    const lib = b.addStaticLibrary(.{
        .name = "ktx_software",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();
    lib.linkLibCpp();
    lib.addIncludePath(b.path("upstream"));
    lib.addIncludePath(b.path("upstream/include"));
    lib.addIncludePath(b.path("upstream/external"));
    lib.addIncludePath(b.path("upstream/external/basisu/zstd"));
    lib.addIncludePath(b.path("upstream/utils"));
    lib.addIncludePath(b.path("upstream/other_include"));
    lib.addIncludePath(b.path("generated"));

    const src_dir = "upstream/";
    lib.addCSourceFiles(.{
        .files = &.{
            src_dir ++ "lib/basis_transcode.cpp",
            src_dir ++ "lib/miniz_wrapper.cpp",
            src_dir ++ "external/basisu/transcoder/basisu_transcoder.cpp",
            src_dir ++ "external/basisu/zstd/zstd.c",
            src_dir ++ "lib/checkheader.c",
            src_dir ++ "external/dfdutils/createdfd.c",
            src_dir ++ "external/dfdutils/colourspaces.c",
            src_dir ++ "external/dfdutils/interpretdfd.c",
            src_dir ++ "external/dfdutils/printdfd.c",
            src_dir ++ "external/dfdutils/queries.c",
            src_dir ++ "external/dfdutils/vk2dfd.c",
            src_dir ++ "lib/etcunpack.cxx",
            src_dir ++ "lib/filestream.c",
            src_dir ++ "lib/hashlist.c",
            src_dir ++ "lib/info.c",
            src_dir ++ "lib/memstream.c",
            src_dir ++ "lib/strings.c",
            src_dir ++ "lib/swap.c",
            src_dir ++ "lib/texture.c",
            src_dir ++ "lib/texture1.c",
            src_dir ++ "lib/texture2.c",
            src_dir ++ "lib/vkformat_check.c",
            src_dir ++ "lib/vkformat_check_variant.c",
            src_dir ++ "lib/vkformat_str.c",
            src_dir ++ "lib/vkformat_typesize.c",

            // ENCODER
            src_dir ++ "external/basisu/encoder/basisu_backend.cpp",
            src_dir ++ "external/basisu/encoder/basisu_basis_file.cpp",
            src_dir ++ "external/basisu/encoder/basisu_bc7enc.cpp",
            src_dir ++ "external/basisu/encoder/basisu_comp.cpp",
            src_dir ++ "external/basisu/encoder/basisu_enc.cpp",
            src_dir ++ "external/basisu/encoder/basisu_etc.cpp",
            src_dir ++ "external/basisu/encoder/basisu_frontend.cpp",
            src_dir ++ "external/basisu/encoder/basisu_gpu_texture.cpp",
            src_dir ++ "external/basisu/encoder/basisu_kernels_sse.cpp",
            src_dir ++ "external/basisu/encoder/basisu_opencl.cpp",
            src_dir ++ "external/basisu/encoder/basisu_pvrtc1_4.cpp",
            src_dir ++ "external/basisu/encoder/basisu_resample_filters.cpp",
            src_dir ++ "external/basisu/encoder/basisu_resampler.cpp",
            src_dir ++ "external/basisu/encoder/basisu_ssim.cpp",
            src_dir ++ "external/basisu/encoder/basisu_uastc_enc.cpp",

            // KTX_FEATURE_VK_UPLOAD
            src_dir ++ "lib/vk_funcs.c",
            src_dir ++ "lib/vkloader.c",

            // KTX_FEATURE_WRITE
            src_dir ++ "lib/basis_encode.cpp",
            src_dir ++ "lib/astc_codec.cpp",
            src_dir ++ "lib/writer1.c",
            src_dir ++ "lib/writer2.c",
        },
        .flags = &.{
            "-DLIBKTX",
            "-DKTX_FEATURE_KTX1",
            "-DKTX_FEATURE_KTX2",
            "-DKTX_FEATURE_VK_UPLOAD",
            "-DKTX_FEATURE_WRITE",
            "-DBASISD_SUPPORT_KTX2_ZSTD=0",
            "-DBASISD_SUPPORT_KTX2=1",
            "-DBASISU_SUPPORT_SSE=0", // TODO: Enable this
            "-DBASISU_SUPPORT_OPENCL=0",
            //"-msse4.1",
            "-DKHRONOS_STATIC",
        },
    });

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    lib.linkLibrary(vulkan_headers.artifact("vulkan_headers"));

    lib.addIncludePath(b.path("../vulkan-headers/upstream/include"));

    b.installArtifact(lib);
}
