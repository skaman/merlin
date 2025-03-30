const std = @import("std");
const builtin = @import("builtin");

const utils = @import("merlin_utils");

const c = @import("c.zig").c;
const platform = @import("platform.zig");

const log = std.log.scoped(.plat_glfw);

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var windows: utils.HandleArray(
    platform.WindowHandle,
    *c.GLFWwindow,
    platform.MaxWindowHandles,
) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    log.err("{s}", .{description});
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(allocator: std.mem.Allocator) !void {
    log.debug("Initializing GLFW renderer", .{});

    gpa = allocator;

    arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena_impl.deinit();
    arena = arena_impl.allocator();

    _ = c.glfwSetErrorCallback(&glfwErrorCallback);

    //c.glfwInitHint(c.GLFW_PLATFORM, c.GLFW_PLATFORM_X11);

    if (c.glfwInit() != c.GLFW_TRUE) {
        log.err("Failed to initialize GLFW", .{});
        return error.GlfwInitFailed;
    }
    errdefer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
}

pub fn deinit() void {
    c.glfwTerminate();

    arena_impl.deinit();
}

pub fn createWindow(handle: platform.WindowHandle, options: *const platform.WindowOptions) !void {
    const window = c.glfwCreateWindow(
        @intCast(options.width),
        @intCast(options.height),
        try arena.dupeZ(u8, options.title),
        null,
        null,
    ) orelse return error.WindowInitFailed;

    windows.setValue(handle, window);
}

pub fn destroyWindow(handle: platform.WindowHandle) void {
    c.glfwDestroyWindow(windows.value(handle));
}

pub fn getWindowFramebufferSize(handle: platform.WindowHandle) [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(windows.value(handle), &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn shouldCloseWindow(handle: platform.WindowHandle) bool {
    return c.glfwWindowShouldClose(windows.value(handle)) == c.GLFW_TRUE;
}

pub fn pollEvents() void {
    _ = arena_impl.reset(.retain_capacity);

    c.glfwPollEvents();
}

pub fn getNativeWindowHandleType() platform.NativeWindowHandleType {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return .wayland;
    }

    return .default;
}
pub fn getNativeWindowHandle(handle: platform.WindowHandle) ?*anyopaque {
    const window = windows.value(handle);
    switch (builtin.os.tag) {
        .linux => {
            if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
                return c.glfwGetWaylandWindow(window);
            return @ptrFromInt(c.glfwGetX11Window(window));
        },
        .windows => return c.glfwGetWin32Window(window),
        .macos => return c.glfwGetCocoaWindow(window),
        else => @compileError("Unsupported OS"),
    }
}
pub fn getNativeDisplayHandle() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return c.glfwGetWaylandDisplay();
        return c.glfwGetX11Display();
    }
    return null;
}
