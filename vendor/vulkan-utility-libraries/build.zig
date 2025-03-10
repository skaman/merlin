const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("vulkan_utility_libraries", .{});

    const lib = b.addStaticLibrary(.{
        .name = "vulkan_utility_libraries",
        .target = target,
        .optimize = optimize,
    });

    const tag = target.result.os.tag;
    if (tag == .windows) {
        lib.root_module.addCMacro("NOMINMAX WIN32_LEAN_AND_MEAN", "");
        lib.root_module.addCMacro("VK_USE_PLATFORM_WIN32_KHR", "");
    } else if (tag == .linux) {
        lib.root_module.addCMacro("VK_USE_PLATFORM_WAYLAND_KHR", "");
        lib.root_module.addCMacro("VK_USE_PLATFORM_XCB_KHR", "");
        lib.root_module.addCMacro("VK_USE_PLATFORM_XLIB_KHR", "");
        lib.root_module.addCMacro("VK_USE_PLATFORM_XLIB_XRANDR_EXT", "");
    } else if (tag == .macos) {
        lib.root_module.addCMacro("VK_USE_PLATFORM_METAL_EXT", "");
        lib.root_module.addCMacro("VK_USE_PLATFORM_MACOS_MVK", "");
    } else {
        std.log.err("Incompatible target platform.", .{});
        std.process.exit(1);
    }

    lib.linkLibCpp();
    lib.addIncludePath(b.path("upstream"));
    lib.addIncludePath(b.path("upstream/include"));

    const src_dir = "upstream/src/";
    lib.addCSourceFiles(.{
        .files = &.{
            // layer
            src_dir ++ "layer/vk_layer_settings.cpp",
            src_dir ++ "layer/vk_layer_settings_helper.cpp",
            src_dir ++ "layer/layer_settings_manager.cpp",
            src_dir ++ "layer/layer_settings_manager.cpp",
            src_dir ++ "layer/layer_settings_util.cpp",
            src_dir ++ "layer/layer_settings_util.cpp",
            // vulkan
            src_dir ++ "vulkan/vk_safe_struct_core.cpp",
            src_dir ++ "vulkan/vk_safe_struct_ext.cpp",
            src_dir ++ "vulkan/vk_safe_struct_khr.cpp",
            src_dir ++ "vulkan/vk_safe_struct_utils.cpp",
            src_dir ++ "vulkan/vk_safe_struct_vendor.cpp",
            src_dir ++ "vulkan/vk_safe_struct_manual.cpp",
        },
    });

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    lib.linkLibrary(vulkan_headers.artifact("vulkan_headers"));

    lib.addIncludePath(b.path("../vulkan-headers/upstream/include"));

    b.installArtifact(lib);
}
