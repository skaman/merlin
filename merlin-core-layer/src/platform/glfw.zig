const std = @import("std");

const c = @import("../c.zig").c;
const gfx = @import("../gfx/gfx.zig");
const platform = @import("platform.zig");

var g_allocator: std.mem.Allocator = undefined;
var g_arena_allocator: std.mem.Allocator = undefined;
var g_windows: [platform.MaxWindowHandles]*c.GLFWwindow = undefined;
var g_default_window: *c.GLFWwindow = undefined;

fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    std.log.err("{s}", .{description});
}

fn glfwFramebufferSizeCallback(_: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
    gfx.invalidateFramebuffer();
}

pub fn glfwCreateWindowSurface(
    instance: c.VkInstance,
    window_handle: platform.WindowHandle,
    allocator: [*c]const c.VkAllocationCallbacks,
    surface: [*c]c.VkSurfaceKHR,
) c.VkResult {
    const window = g_windows[window_handle];
    return c.glfwCreateWindowSurface(instance, window, allocator, surface);
}

pub fn glfwCreateDefaultWindowSurface(
    instance: c.VkInstance,
    allocator: [*c]const c.VkAllocationCallbacks,
    surface: [*c]c.VkSurfaceKHR,
) c.VkResult {
    return c.glfwCreateWindowSurface(instance, g_default_window, allocator, surface);
}

pub fn glfwGetFramebufferSize(window_handle: platform.WindowHandle, width: *c_int, height: *c_int) void {
    const window = g_windows[window_handle];
    c.glfwGetFramebufferSize(window, width, height);
}

pub fn glfwGetDefaultFramebufferSize(width: *c_int, height: *c_int) void {
    c.glfwGetFramebufferSize(g_default_window, width, height);
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

    _ = c.glfwSetFramebufferSizeCallback(g_default_window, &glfwFramebufferSizeCallback);
}

pub fn deinit() void {
    c.glfwDestroyWindow(g_default_window);
    c.glfwTerminate();
}

pub fn createWindow(handle: platform.WindowHandle, options: *const platform.WindowOptions) !void {
    const window = c.glfwCreateWindow(
        @intCast(options.width),
        @intCast(options.height),
        try g_arena_allocator.dupeZ(u8, options.window.title),
        null,
        null,
    ) orelse return error.WindowInitFailed;

    _ = c.glfwSetFramebufferSizeCallback(window, &glfwFramebufferSizeCallback);

    g_windows[handle] = window;
}

pub fn destroyWindow(handle: platform.WindowHandle) void {
    c.glfwDestroyWindow(g_windows[handle]);
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
