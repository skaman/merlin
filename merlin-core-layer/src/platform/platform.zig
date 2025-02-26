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

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    createWindow: *const fn (handle: WindowHandle, options: *const WindowOptions) anyerror!void,
    destroyWindow: *const fn (handle: WindowHandle) void,
    shouldCloseDefaultWindow: *const fn () bool,
    shouldCloseWindow: *const fn (handle: WindowHandle) bool,
    pollEvents: *const fn () void,
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
            .shouldCloseDefaultWindow = noop.shouldCloseDefaultWindow,
            .shouldCloseWindow = noop.shouldCloseWindow,
            .pollEvents = noop.pollEvents,
        },
        Type.glfw => return VTab{
            .init = glfw.init,
            .deinit = glfw.deinit,
            .createWindow = glfw.createWindow,
            .destroyWindow = glfw.destroyWindow,
            .shouldCloseDefaultWindow = glfw.shouldCloseDefaultWindow,
            .shouldCloseWindow = glfw.shouldCloseWindow,
            .pollEvents = glfw.pollEvents,
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
