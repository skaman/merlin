const std = @import("std");

const c = @import("../c.zig").c;
const gfx = @import("../gfx/gfx.zig");
const platform = @import("platform.zig");

var g_windows: [platform.MaxWindowHandles]*c.GLFWwindow = undefined;

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

pub fn glfwGetFramebufferSize(window_handle: platform.WindowHandle, width: *c_int, height: *c_int) void {
    const window = g_windows[window_handle];
    c.glfwGetFramebufferSize(window, width, height);
}

pub fn init() !void {
    _ = c.glfwSetErrorCallback(&glfwErrorCallback);

    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    errdefer c.glfwTerminate();
}

pub fn deinit() void {
    c.glfwTerminate();
}

pub fn createWindow(handle: platform.WindowHandle, options: *const platform.WindowOptions) !void {
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(
        @intCast(options.width),
        @intCast(options.height),
        "TEST", //options.title,
        null,
        null,
    ) orelse return error.WindowInitFailed;

    _ = c.glfwSetFramebufferSizeCallback(window, &glfwFramebufferSizeCallback);

    g_windows[handle] = window;
}

pub fn destroyWindow(handle: platform.WindowHandle) void {
    c.glfwDestroyWindow(g_windows[handle]);
}

pub fn shouldCloseWindow(handle: platform.WindowHandle) bool {
    return c.glfwWindowShouldClose(g_windows[handle]) == c.GLFW_TRUE;
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}
