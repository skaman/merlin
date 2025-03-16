const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_platform = b.dependency("merlin_platform", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });
    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    const vulkan_headers = b.dependency("vulkan_headers", .{
        .target = target,
        .optimize = optimize,
    });
    const vulkan_utility_libraries = b.dependency("vulkan_utility_libraries", .{
        .target = target,
        .optimize = optimize,
    });
    const ktx_software = b.dependency("ktx_software", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_gfx_mod = b.addModule("merlin_gfx", .{
        .root_source_file = b.path("src/gfx.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_gfx = b.addLibrary(.{
        .name = "merlin_gfx",
        .root_module = merlin_gfx_mod,
    });
    b.installArtifact(merlin_gfx);

    merlin_gfx.root_module.addImport("merlin_platform", merlin_platform.module("merlin_platform"));
    merlin_gfx.root_module.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    merlin_gfx.root_module.addImport("zmath", zmath.module("root"));

    merlin_gfx.linkLibrary(vulkan_headers.artifact("vulkan_headers"));
    merlin_gfx.addIncludePath(b.path("../vendor/vulkan-headers/upstream/include"));
    merlin_gfx.linkLibrary(vulkan_utility_libraries.artifact("vulkan_utility_libraries"));
    merlin_gfx.addIncludePath(b.path("../vendor/vulkan-utility-libraries/upstream/include"));
    merlin_gfx.linkLibrary(ktx_software.artifact("ktx_software"));
    merlin_gfx.addIncludePath(b.path("../vendor/ktx-software/upstream/include"));

    switch (builtin.target.os.tag) {
        .windows => {
            merlin_gfx_mod.addCMacro("VK_USE_PLATFORM_WIN32_KHR", "");
        },
        .linux => {
            merlin_gfx_mod.addCMacro("VK_USE_PLATFORM_XCB_KHR", "");
            merlin_gfx_mod.addCMacro("VK_USE_PLATFORM_XLIB_KHR", "");
            merlin_gfx_mod.addCMacro("VK_USE_PLATFORM_WAYLAND_KHR", "");
            merlin_gfx.addIncludePath(b.path("../vendor/system/linux/xcb/include"));
            merlin_gfx.addIncludePath(b.path("../vendor/system/linux/x11/include"));
            merlin_gfx.addIncludePath(b.path("../vendor/system/linux/xorgproto/include"));
            merlin_gfx.addIncludePath(b.path("../vendor/system/linux/xrandr/include"));
            merlin_gfx.addIncludePath(b.path("../vendor/system/linux/xrender/include"));
            merlin_gfx.addIncludePath(b.path("../vendor/system/linux/wayland/include"));
        },
        .macos => {
            merlin_gfx_mod.addCMacro("VK_USE_PLATFORM_MACOS_MVK", "");
        },
        else => @compileError("Unsupported OS"),
    }
}
