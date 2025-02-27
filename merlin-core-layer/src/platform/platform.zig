const std = @import("std");

const utils = @import("../utils.zig");
const glfw = @import("glfw.zig");
const noop = @import("noop.zig");

pub const log = std.log.scoped(.gfx);

const Type = enum {
    noop,
    glfw,
};

pub const Options = struct {
    type: Type,
    window: WindowOptions,
};

pub const WindowOptions = struct {
    width: u32,
    height: u32,
    title: []const u8,
};

pub const NativeWindowHandleType = enum(u8) {
    default, //  Platform default handle type (X11 on Linux).
    wayland,
};

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    createWindow: *const fn (handle: WindowHandle, options: *const WindowOptions) anyerror!void,
    destroyWindow: *const fn (handle: WindowHandle) void,
    getDefaultWindowFramebufferSize: *const fn () [2]u32,
    getWindowFramebufferSize: *const fn (handle: WindowHandle) [2]u32,
    shouldCloseDefaultWindow: *const fn () bool,
    shouldCloseWindow: *const fn (handle: WindowHandle) bool,
    pollEvents: *const fn () void,
    getNativeWindowHandleType: *const fn () NativeWindowHandleType,
    getNativeDefaultWindowHandle: *const fn () ?*anyopaque,
    getNativeDefaultDisplayHandle: *const fn () ?*anyopaque,
};

pub const WindowHandle = u16;
pub const MaxWindowHandles = 64;

var g_window_handles: utils.HandlePool(WindowHandle, MaxWindowHandles) = .init();

var g_platform_v_tab: VTab = undefined;

fn getVTab(
    platform_type: Type,
) !VTab {
    switch (platform_type) {
        Type.noop => return VTab{
            .init = noop.init,
            .deinit = noop.deinit,
            .createWindow = noop.createWindow,
            .destroyWindow = noop.destroyWindow,
            .getDefaultWindowFramebufferSize = noop.getDefaultWindowFramebufferSize,
            .getWindowFramebufferSize = noop.getWindowFramebufferSize,
            .shouldCloseDefaultWindow = noop.shouldCloseDefaultWindow,
            .shouldCloseWindow = noop.shouldCloseWindow,
            .pollEvents = noop.pollEvents,
            .getNativeWindowHandleType = noop.getNativeWindowHandleType,
            .getNativeDefaultWindowHandle = noop.getNativeDefaultWindowHandle,
            .getNativeDefaultDisplayHandle = noop.getNativeDefaultDisplayHandle,
        },
        Type.glfw => return VTab{
            .init = glfw.init,
            .deinit = glfw.deinit,
            .createWindow = glfw.createWindow,
            .destroyWindow = glfw.destroyWindow,
            .getDefaultWindowFramebufferSize = glfw.getDefaultWindowFramebufferSize,
            .getWindowFramebufferSize = glfw.getWindowFramebufferSize,
            .shouldCloseDefaultWindow = glfw.shouldCloseDefaultWindow,
            .shouldCloseWindow = glfw.shouldCloseWindow,
            .pollEvents = glfw.pollEvents,
            .getNativeWindowHandleType = glfw.getNativeWindowHandleType,
            .getNativeDefaultWindowHandle = glfw.getNativeDefaultWindowHandle,
            .getNativeDefaultDisplayHandle = glfw.getNativeDefaultDisplayHandle,
        },
    }
}

pub fn init(
    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: Options,
) !void {
    log.debug("Initializing platform", .{});

    g_platform_v_tab = try getVTab(options.type);
    try g_platform_v_tab.init(allocator, arena_allocator, &options);
}

pub fn deinit() void {
    log.debug("Deinitializing platform", .{});
    g_platform_v_tab.deinit();
}

pub fn createWindow(
    options: WindowOptions,
) !WindowHandle {
    const handle = try g_window_handles.alloc();
    errdefer g_window_handles.free(handle);

    try g_platform_v_tab.createWindow(handle, &options);
    return handle;
}

pub fn destroyWindow(
    handle: WindowHandle,
) void {
    g_platform_v_tab.destroyWindow(handle);
    g_window_handles.free(handle);
}

pub fn getDefaultWindowFramebufferSize() [2]u32 {
    return g_platform_v_tab.getDefaultWindowFramebufferSize();
}

pub fn getWindowFramebufferSize(
    handle: WindowHandle,
) [2]u32 {
    return g_platform_v_tab.getWindowFramebufferSize(handle);
}

pub fn shouldCloseDefaultWindow() bool {
    return g_platform_v_tab.shouldCloseDefaultWindow();
}

pub fn shouldCloseWindow(
    handle: WindowHandle,
) bool {
    return g_platform_v_tab.shouldCloseWindow(handle);
}

pub fn pollEvents() void {
    g_platform_v_tab.pollEvents();
}

pub fn getNativeWindowHandleType() NativeWindowHandleType {
    return g_platform_v_tab.getNativeWindowHandleType();
}

pub fn getNativeDefaultWindowHandle() ?*anyopaque {
    return g_platform_v_tab.getNativeDefaultWindowHandle();
}

pub fn getNativeDefaultDisplayHandle() ?*anyopaque {
    return g_platform_v_tab.getNativeDefaultDisplayHandle();
}
