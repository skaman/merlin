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
    init: *const fn (allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator) anyerror!void,
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

pub const WindowHandle = u16;
pub const MaxWindowHandles = 64;

var g_gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var g_allocator: std.mem.Allocator = undefined;

var g_arena: std.heap.ArenaAllocator = undefined;
var g_arena_allocator: std.mem.Allocator = undefined;

var g_default_window_handle: WindowHandle = 0;
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
    options: Options,
) !void {
    log.debug("Initializing platform", .{});

    g_platform_v_tab = try getVTab(options.type);

    g_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = g_gpa.deinit();
    g_allocator = g_gpa.allocator();

    g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer g_arena.deinit();
    g_arena_allocator = g_arena.allocator();

    try g_platform_v_tab.init(g_allocator, g_arena_allocator);
    errdefer g_platform_v_tab.deinit();

    g_default_window_handle = try createWindow(options.window);
}

pub fn deinit() void {
    log.debug("Deinitializing platform", .{});

    destroyWindow(g_default_window_handle);

    g_platform_v_tab.deinit();

    g_arena.deinit();
    _ = g_gpa.deinit();
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

pub fn getWindowFramebufferSize(
    handle: WindowHandle,
) [2]u32 {
    return g_platform_v_tab.getWindowFramebufferSize(handle);
}

pub fn getDefaultWindowFramebufferSize() [2]u32 {
    return getWindowFramebufferSize(g_default_window_handle);
}

pub fn shouldCloseWindow(
    handle: WindowHandle,
) bool {
    return g_platform_v_tab.shouldCloseWindow(handle);
}

pub fn shouldCloseDefaultWindow() bool {
    return shouldCloseWindow(g_default_window_handle);
}

pub fn pollEvents() void {
    _ = g_arena.reset(.retain_capacity);

    g_platform_v_tab.pollEvents();
}

pub fn getNativeWindowHandleType() NativeWindowHandleType {
    return g_platform_v_tab.getNativeWindowHandleType();
}

pub fn getNativeWindowHandle(
    handle: WindowHandle,
) ?*anyopaque {
    return g_platform_v_tab.getNativeWindowHandle(handle);
}

pub fn getNativeDefaultWindowHandle() ?*anyopaque {
    return getNativeWindowHandle(g_default_window_handle);
}

pub fn getNativeDisplayHandle() ?*anyopaque {
    return g_platform_v_tab.getNativeDisplayHandle();
}
