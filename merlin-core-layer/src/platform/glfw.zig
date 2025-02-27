const std = @import("std");
const builtin = @import("builtin");

const c = @import("../c.zig").c;
const platform = @import("platform.zig");

var g_allocator: std.mem.Allocator = undefined;
var g_arena_allocator: std.mem.Allocator = undefined;
var g_windows: [platform.MaxWindowHandles]*c.GLFWwindow = undefined;
var g_default_window: *c.GLFWwindow = undefined;

fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    std.log.err("{s}", .{description});
}

pub fn init(
    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: *const platform.Options,
) !void {
    g_allocator = allocator;
    g_arena_allocator = arena_allocator;

    _ = c.glfwSetErrorCallback(&glfwErrorCallback);

    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    errdefer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    g_default_window = c.glfwCreateWindow(
        @intCast(options.window.width),
        @intCast(options.window.height),
        try arena_allocator.dupeZ(u8, options.window.title),
        null,
        null,
    ) orelse return error.WindowInitFailed;
    errdefer c.glfwDestroyWindow(g_default_window);

    //_ = c.glfwSetFramebufferSizeCallback(g_default_window, &glfwFramebufferSizeCallback);
}

pub fn deinit() void {
    c.glfwDestroyWindow(g_default_window);
    c.glfwTerminate();
}

pub fn createWindow(handle: platform.WindowHandle, options: *const platform.WindowOptions) !void {
    const window = c.glfwCreateWindow(
        @intCast(options.width),
        @intCast(options.height),
        try g_arena_allocator.dupeZ(u8, options.title),
        null,
        null,
    ) orelse return error.WindowInitFailed;

    //_ = c.glfwSetFramebufferSizeCallback(window, &glfwFramebufferSizeCallback);

    g_windows[handle] = window;
}

pub fn destroyWindow(handle: platform.WindowHandle) void {
    c.glfwDestroyWindow(g_windows[handle]);
}

pub fn getDefaultWindowFramebufferSize() [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(g_default_window, &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn getWindowFramebufferSize(handle: platform.WindowHandle) [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(g_windows[handle], &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn shouldCloseDefaultWindow() bool {
    return c.glfwWindowShouldClose(g_default_window) == c.GLFW_TRUE;
}

pub fn shouldCloseWindow(handle: platform.WindowHandle) bool {
    return c.glfwWindowShouldClose(g_windows[handle]) == c.GLFW_TRUE;
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

pub fn getNativeWindowHandleType() platform.NativeWindowHandleType {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return .wayland;
    }

    return .default;
}
pub fn getNativeDefaultWindowHandle() ?*anyopaque {
    switch (builtin.os.tag) {
        .linux => {
            if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
                return c.glfwGetWaylandWindow(g_default_window);
            return @ptrFromInt(c.glfwGetX11Window(g_default_window));
        },
        .windows => return c.glfwGetWin32Window(g_default_window),
        .macos => return c.glfwGetCocoaWindow(g_default_window),
        else => @compileError("Unsupported OS"),
    }
}
pub fn getNativeDefaultDisplayHandle() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return c.glfwGetWaylandDisplay();
        return c.glfwGetX11Display();
    }
    return null;
}
