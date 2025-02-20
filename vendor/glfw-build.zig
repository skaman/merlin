const std = @import("std");

pub fn addLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    enable_x11: bool,
    enable_wayland: bool,
) *std.Build.Step.Compile {
    const glfw = b.addStaticLibrary(.{
        .name = "glfw",
        .target = target,
        .optimize = optimize,
    });
    glfw.addIncludePath(b.path("vendor/glfw/include"));
    glfw.linkLibC();
    const src_dir = "vendor/glfw/src/";
    switch (target.result.os.tag) {
        .windows => {
            glfw.linkSystemLibrary("gdi32");
            glfw.linkSystemLibrary("user32");
            glfw.linkSystemLibrary("shell32");
            glfw.addCSourceFiles(.{
                .files = &.{
                    src_dir ++ "platform.c",
                    src_dir ++ "monitor.c",
                    src_dir ++ "init.c",
                    src_dir ++ "vulkan.c",
                    src_dir ++ "input.c",
                    src_dir ++ "context.c",
                    src_dir ++ "window.c",
                    src_dir ++ "osmesa_context.c",
                    src_dir ++ "egl_context.c",
                    src_dir ++ "null_init.c",
                    src_dir ++ "null_monitor.c",
                    src_dir ++ "null_window.c",
                    src_dir ++ "null_joystick.c",
                    src_dir ++ "wgl_context.c",
                    src_dir ++ "win32_thread.c",
                    src_dir ++ "win32_init.c",
                    src_dir ++ "win32_monitor.c",
                    src_dir ++ "win32_time.c",
                    src_dir ++ "win32_joystick.c",
                    src_dir ++ "win32_window.c",
                    src_dir ++ "win32_module.c",
                },
                .flags = &.{"-D_GLFW_WIN32"},
            });
        },
        .macos => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                glfw.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
                glfw.addSystemIncludePath(system_sdk.path("macos12/usr/include"));
                glfw.addLibraryPath(system_sdk.path("macos12/usr/lib"));
            }
            glfw.linkSystemLibrary("objc");
            glfw.linkFramework("IOKit");
            glfw.linkFramework("CoreFoundation");
            glfw.linkFramework("Metal");
            glfw.linkFramework("AppKit");
            glfw.linkFramework("CoreServices");
            glfw.linkFramework("CoreGraphics");
            glfw.linkFramework("Foundation");
            glfw.addCSourceFiles(.{
                .files = &.{
                    src_dir ++ "platform.c",
                    src_dir ++ "monitor.c",
                    src_dir ++ "init.c",
                    src_dir ++ "vulkan.c",
                    src_dir ++ "input.c",
                    src_dir ++ "context.c",
                    src_dir ++ "window.c",
                    src_dir ++ "osmesa_context.c",
                    src_dir ++ "egl_context.c",
                    src_dir ++ "null_init.c",
                    src_dir ++ "null_monitor.c",
                    src_dir ++ "null_window.c",
                    src_dir ++ "null_joystick.c",
                    src_dir ++ "posix_thread.c",
                    src_dir ++ "posix_module.c",
                    src_dir ++ "posix_poll.c",
                    src_dir ++ "nsgl_context.m",
                    src_dir ++ "cocoa_time.c",
                    src_dir ++ "cocoa_joystick.m",
                    src_dir ++ "cocoa_init.m",
                    src_dir ++ "cocoa_window.m",
                    src_dir ++ "cocoa_monitor.m",
                },
                .flags = &.{"-D_GLFW_COCOA"},
            });
        },
        .linux => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                glfw.addSystemIncludePath(system_sdk.path("linux/include"));
                glfw.addSystemIncludePath(system_sdk.path("linux/include/wayland"));
                glfw.addIncludePath(b.path(src_dir ++ "wayland"));

                if (target.result.cpu.arch.isX86()) {
                    glfw.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
                } else {
                    glfw.addLibraryPath(system_sdk.path("linux/lib/aarch64-linux-gnu"));
                }
            }
            glfw.addCSourceFiles(.{
                .files = &.{
                    src_dir ++ "platform.c",
                    src_dir ++ "monitor.c",
                    src_dir ++ "init.c",
                    src_dir ++ "vulkan.c",
                    src_dir ++ "input.c",
                    src_dir ++ "context.c",
                    src_dir ++ "window.c",
                    src_dir ++ "osmesa_context.c",
                    src_dir ++ "egl_context.c",
                    src_dir ++ "null_init.c",
                    src_dir ++ "null_monitor.c",
                    src_dir ++ "null_window.c",
                    src_dir ++ "null_joystick.c",
                    src_dir ++ "posix_time.c",
                    src_dir ++ "posix_thread.c",
                    src_dir ++ "posix_module.c",
                    src_dir ++ "egl_context.c",
                },
                .flags = &.{},
            });
            if (enable_x11 or enable_wayland) {
                glfw.addCSourceFiles(.{
                    .files = &.{
                        src_dir ++ "xkb_unicode.c",
                        src_dir ++ "linux_joystick.c",
                        src_dir ++ "posix_poll.c",
                    },
                    .flags = &.{},
                });
            }
            if (enable_x11) {
                glfw.addCSourceFiles(.{
                    .files = &.{
                        src_dir ++ "x11_init.c",
                        src_dir ++ "x11_monitor.c",
                        src_dir ++ "x11_window.c",
                        src_dir ++ "glx_context.c",
                    },
                    .flags = &.{},
                });
                glfw.root_module.addCMacro("_GLFW_X11", "1");
                glfw.linkSystemLibrary("X11");
            }
            if (enable_wayland) {
                glfw.addCSourceFiles(.{
                    .files = &.{
                        src_dir ++ "wl_init.c",
                        src_dir ++ "wl_monitor.c",
                        src_dir ++ "wl_window.c",
                    },
                    .flags = &.{},
                });
                glfw.root_module.addCMacro("_GLFW_WAYLAND", "1");
            }
        },
        else => {},
    }

    return glfw;
}

pub fn linkLibrary(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    glfw: *std.Build.Step.Compile,
) void {
    exe.linkLibrary(glfw);
    exe.addIncludePath(b.path("vendor/glfw/include/"));
}
