const std = @import("std");

const utils = @import("merlin_utils");

const glfw = @import("glfw.zig");
const noop = @import("noop.zig");

pub const log = std.log.scoped(.gfx);

pub const WindowHandle = enum(u16) { _ };
pub const MaxWindowHandles = 64;

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

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
    init: *const fn (allocator: std.mem.Allocator) anyerror!void,
    deinit: *const fn () void,
    createWindow: *const fn (handle: WindowHandle, options: *const WindowOptions) anyerror!void,
    destroyWindow: *const fn (handle: WindowHandle) void,
    getWindowFramebufferSize: *const fn (handle: WindowHandle) [2]u32,
    shouldCloseWindow: *const fn (handle: WindowHandle) bool,
    pollEvents: *const fn () void,
    getNativeWindowHandleType: *const fn () NativeWindowHandleType,
    getNativeWindowHandle: *const fn (handle: WindowHandle) ?*anyopaque,
    getNativeDisplayHandle: *const fn () ?*anyopaque,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var default_window_handle: WindowHandle = undefined;
var window_handles: utils.HandlePool(WindowHandle, MaxWindowHandles) = undefined;

var v_tab: VTab = undefined;

fn getVTab(
    platform_type: Type,
) !VTab {
    switch (platform_type) {
        Type.noop => return VTab{
            .init = noop.init,
            .deinit = noop.deinit,
            .createWindow = noop.createWindow,
            .destroyWindow = noop.destroyWindow,
            .getWindowFramebufferSize = noop.getWindowFramebufferSize,
            .shouldCloseWindow = noop.shouldCloseWindow,
            .pollEvents = noop.pollEvents,
            .getNativeWindowHandleType = noop.getNativeWindowHandleType,
            .getNativeWindowHandle = noop.getNativeWindowHandle,
            .getNativeDisplayHandle = noop.getNativeDisplayHandle,
        },
        Type.glfw => return VTab{
            .init = glfw.init,
            .deinit = glfw.deinit,
            .createWindow = glfw.createWindow,
            .destroyWindow = glfw.destroyWindow,
            .getWindowFramebufferSize = glfw.getWindowFramebufferSize,
            .shouldCloseWindow = glfw.shouldCloseWindow,
            .pollEvents = glfw.pollEvents,
            .getNativeWindowHandleType = glfw.getNativeWindowHandleType,
            .getNativeWindowHandle = glfw.getNativeWindowHandle,
            .getNativeDisplayHandle = glfw.getNativeDisplayHandle,
        },
    }
}

pub fn init(
    allocator: std.mem.Allocator,
    options: Options,
) !void {
    log.debug("Initializing platform", .{});

    v_tab = try getVTab(options.type);
    window_handles = .init();

    try v_tab.init(allocator);
    errdefer v_tab.deinit();

    default_window_handle = try createWindow(options.window);
}

pub fn deinit() void {
    log.debug("Deinitializing platform", .{});

    destroyWindow(default_window_handle);

    v_tab.deinit();

    window_handles.deinit();
}

pub fn createWindow(options: WindowOptions) !WindowHandle {
    const handle = window_handles.create();
    errdefer window_handles.destroy(handle);

    try v_tab.createWindow(handle, &options);
    return handle;
}

pub fn destroyWindow(handle: WindowHandle) void {
    v_tab.destroyWindow(handle);
    window_handles.destroy(handle);
}

pub inline fn getWindowFramebufferSize(handle: WindowHandle) [2]u32 {
    return v_tab.getWindowFramebufferSize(handle);
}

pub inline fn getDefaultWindowFramebufferSize() [2]u32 {
    return getWindowFramebufferSize(default_window_handle);
}

pub inline fn shouldCloseWindow(handle: WindowHandle) bool {
    return v_tab.shouldCloseWindow(handle);
}

pub inline fn shouldCloseDefaultWindow() bool {
    return shouldCloseWindow(default_window_handle);
}

pub inline fn pollEvents() void {
    v_tab.pollEvents();
}

pub inline fn getNativeWindowHandleType() NativeWindowHandleType {
    return v_tab.getNativeWindowHandleType();
}

pub inline fn getNativeWindowHandle(handle: WindowHandle) ?*anyopaque {
    return v_tab.getNativeWindowHandle(handle);
}

pub inline fn getNativeDefaultWindowHandle() ?*anyopaque {
    return getNativeWindowHandle(default_window_handle);
}

pub inline fn getNativeDisplayHandle() ?*anyopaque {
    return v_tab.getNativeDisplayHandle();
}
