const std = @import("std");
const builtin = @import("builtin");

const utils = @import("merlin_utils");

const c = @import("c.zig").c;
const platform = @import("platform.zig");

const log = std.log.scoped(.plat_glfw);

const MemoryAlignment = 16; // Should be fine on x86_64 and ARM64

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var _gpa: std.mem.Allocator = undefined;
var _arena_impl: std.heap.ArenaAllocator = undefined;
var _arena: std.mem.Allocator = undefined;

var _cursors: [@typeInfo(platform.Cursor).@"enum".fields.len]?*c.GLFWcursor = undefined;

var _window_focus_callbacks: std.ArrayList(platform.WindowFocusCallback) = undefined;
var _cursor_position_callbacks: std.ArrayList(platform.CursorPositionCallback) = undefined;
var _mouse_button_callbacks: std.ArrayList(platform.MouseButtonCallback) = undefined;
var _mouse_scroll_callbacks: std.ArrayList(platform.MouseScrollCallback) = undefined;
var _key_callbacks: std.ArrayList(platform.KeyCallback) = undefined;
var _char_callbacks: std.ArrayList(platform.CharCallback) = undefined;
var _window_close_callbacks: std.ArrayList(platform.WindowCloseCallback) = undefined;
var _window_position_callbacks: std.ArrayList(platform.WindowPositionCallback) = undefined;
var _window_size_callbacks: std.ArrayList(platform.WindowSizeCallback) = undefined;
var _windows_to_destroy: std.ArrayList(platform.WindowHandle) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn glfwAllocateCallback(size: usize, _: ?*anyopaque) callconv(.c) ?*anyopaque {
    const raw_allocator = utils.RawAllocator.init(_gpa);
    return raw_allocator.allocate(size, MemoryAlignment);
}

fn glfwReallocateCallback(
    original: ?*anyopaque,
    size: usize,
    _: ?*anyopaque,
) callconv(.c) ?*anyopaque {
    const raw_allocator = utils.RawAllocator.init(_gpa);
    return raw_allocator.reallocate(
        @ptrCast(original),
        size,
        MemoryAlignment,
    );
}

fn glfwDeallocateCallback(
    ptr: ?*anyopaque,
    _: ?*anyopaque,
) callconv(.c) void {
    const raw_allocator = utils.RawAllocator.init(_gpa);
    raw_allocator.free(@ptrCast(ptr));
}

fn parseModifiers(mod: c_int) platform.KeyModifier {
    return platform.KeyModifier{
        .shift = (mod & c.GLFW_MOD_SHIFT) != 0,
        .control = (mod & c.GLFW_MOD_CONTROL) != 0,
        .alt = (mod & c.GLFW_MOD_ALT) != 0,
        .super = (mod & c.GLFW_MOD_SUPER) != 0,
        .caps_lock = (mod & c.GLFW_MOD_CAPS_LOCK) != 0,
        .num_lock = (mod & c.GLFW_MOD_NUM_LOCK) != 0,
    };
}

fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    log.err("{s}", .{description});
}

fn glfwWindowFocusCallback(
    window: ?*c.GLFWwindow,
    focused: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };
    const focused_ = focused == c.GLFW_TRUE;

    for (_window_focus_callbacks.items) |callback| {
        callback(handle, focused_);
    }
}

fn glfwCursorPositionCallback(
    window: ?*c.GLFWwindow,
    xpos: f64,
    ypos: f64,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };

    for (_cursor_position_callbacks.items) |callback| {
        callback(handle, .{ @floatCast(xpos), @floatCast(ypos) });
    }
}

fn glfwMouseButtonCallback(
    window: ?*c.GLFWwindow,
    button: c_int,
    action: c_int,
    mod: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };
    const button_: platform.MouseButton = @enumFromInt(button);
    const action_ = switch (action) {
        c.GLFW_PRESS => platform.MouseButtonAction.press,
        c.GLFW_RELEASE => platform.MouseButtonAction.release,
        else => return,
    };
    const modifiers = parseModifiers(mod);

    for (_mouse_button_callbacks.items) |callback| {
        callback(handle, button_, action_, modifiers);
    }
}

fn glfwMouseScrollCallback(
    window: ?*c.GLFWwindow,
    x_scroll: f64,
    y_scroll: f64,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };

    for (_mouse_scroll_callbacks.items) |callback| {
        callback(handle, @floatCast(x_scroll), @floatCast(y_scroll));
    }
}

fn glfwKeyCallback(
    window: ?*c.GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mod: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };
    const action_ = switch (action) {
        c.GLFW_PRESS => platform.KeyAction.press,
        c.GLFW_RELEASE => platform.KeyAction.release,
        c.GLFW_REPEAT => platform.KeyAction.repeat,
        else => return,
    };
    const key_ = std.meta.intToEnum(platform.Key, key) catch {
        log.err("Invalid key: {}", .{key});
        return;
    };
    const modifiers = parseModifiers(mod);

    for (_key_callbacks.items) |callback| {
        callback(handle, key_, scancode, action_, modifiers);
    }
}

fn glfwCharCallback(
    window: ?*c.GLFWwindow,
    codepoint: c_uint,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };

    for (_char_callbacks.items) |callback| {
        callback(handle, codepoint);
    }
}

fn glfwWindowCloseCallback(
    window: ?*c.GLFWwindow,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };

    for (_window_close_callbacks.items) |callback| {
        callback(handle);
    }
}

fn glfwWindowPositionCallback(
    window: ?*c.GLFWwindow,
    xpos: c_int,
    ypos: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };

    for (_window_position_callbacks.items) |callback| {
        callback(handle, .{ @intCast(xpos), @intCast(ypos) });
    }
}

fn glfwWindowSizeCallback(
    window: ?*c.GLFWwindow,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = .{ .handle = @ptrCast(window) };

    for (_window_size_callbacks.items) |callback| {
        callback(handle, .{ @intCast(width), @intCast(height) });
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(allocator: std.mem.Allocator) !void {
    log.debug("Initializing GLFW renderer", .{});

    _gpa = allocator;

    _arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer _arena_impl.deinit();
    _arena = _arena_impl.allocator();

    _window_focus_callbacks = .init(_gpa);
    errdefer _window_focus_callbacks.deinit();

    _cursor_position_callbacks = .init(_gpa);
    errdefer _cursor_position_callbacks.deinit();

    _mouse_button_callbacks = .init(_gpa);
    errdefer _mouse_button_callbacks.deinit();

    _mouse_scroll_callbacks = .init(_gpa);
    errdefer _mouse_scroll_callbacks.deinit();

    _key_callbacks = .init(_gpa);
    errdefer _key_callbacks.deinit();

    _char_callbacks = .init(_gpa);
    errdefer _char_callbacks.deinit();

    _window_close_callbacks = .init(_gpa);
    errdefer _window_close_callbacks.deinit();

    _window_position_callbacks = .init(_gpa);
    errdefer _window_position_callbacks.deinit();

    _window_size_callbacks = .init(_gpa);
    errdefer _window_size_callbacks.deinit();

    _windows_to_destroy = .init(_gpa);
    errdefer _windows_to_destroy.deinit();

    _ = c.glfwSetErrorCallback(&glfwErrorCallback);

    const glfw_allocator = c.GLFWallocator{
        .user = null,
        .allocate = &glfwAllocateCallback,
        .reallocate = &glfwReallocateCallback,
        .deallocate = &glfwDeallocateCallback,
    };
    c.glfwInitAllocator(&glfw_allocator);

    // c.glfwInitHint(c.GLFW_PLATFORM, c.GLFW_PLATFORM_X11);

    if (c.glfwInit() != c.GLFW_TRUE) {
        log.err("Failed to initialize GLFW", .{});
        return error.GlfwInitFailed;
    }
    errdefer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    _cursors = .{
        c.glfwCreateStandardCursor(c.GLFW_ARROW_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_HAND_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_IBEAM_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_RESIZE_ALL_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_VRESIZE_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_HRESIZE_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_RESIZE_NESW_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_RESIZE_NWSE_CURSOR),
        c.glfwCreateStandardCursor(c.GLFW_NOT_ALLOWED_CURSOR),
    };
}

pub fn deinit() void {
    for (_cursors) |cursor_| {
        c.glfwDestroyCursor(cursor_);
    }

    _windows_to_destroy.deinit();
    _window_size_callbacks.deinit();
    _window_position_callbacks.deinit();
    _window_close_callbacks.deinit();
    _char_callbacks.deinit();
    _key_callbacks.deinit();
    _mouse_scroll_callbacks.deinit();
    _mouse_button_callbacks.deinit();
    _cursor_position_callbacks.deinit();
    _window_focus_callbacks.deinit();

    c.glfwTerminate();

    _arena_impl.deinit();
}

pub fn createWindow(options: *const platform.WindowOptions) !platform.WindowHandle {
    c.glfwWindowHint(c.GLFW_VISIBLE, @intFromBool(options.visible));
    c.glfwWindowHint(c.GLFW_FOCUSED, @intFromBool(options.focused));
    c.glfwWindowHint(c.GLFW_FOCUS_ON_SHOW, @intFromBool(options.focused));
    c.glfwWindowHint(c.GLFW_DECORATED, @intFromBool(options.decorated));
    c.glfwWindowHint(c.GLFW_FLOATING, @intFromBool(options.floating));

    const window = c.glfwCreateWindow(
        @intCast(options.width),
        @intCast(options.height),
        try _arena.dupeZ(u8, options.title),
        null,
        null,
    ) orelse return error.WindowInitFailed;

    _ = c.glfwSetWindowFocusCallback(window, &glfwWindowFocusCallback);
    _ = c.glfwSetCursorPosCallback(window, &glfwCursorPositionCallback);
    _ = c.glfwSetMouseButtonCallback(window, &glfwMouseButtonCallback);
    _ = c.glfwSetScrollCallback(window, &glfwMouseScrollCallback);
    _ = c.glfwSetKeyCallback(window, &glfwKeyCallback);
    _ = c.glfwSetCharCallback(window, &glfwCharCallback);
    _ = c.glfwSetWindowCloseCallback(window, &glfwWindowCloseCallback);
    _ = c.glfwSetWindowPosCallback(window, &glfwWindowPositionCallback);
    _ = c.glfwSetWindowSizeCallback(window, &glfwWindowSizeCallback);

    return .{ .handle = @ptrCast(window) };
}

pub fn destroyWindow(handle: platform.WindowHandle) void {
    _windows_to_destroy.append(handle) catch |err| {
        log.err("Failed to append window to destroy list: {}", .{err});
    };
}

pub fn showWindow(handle: platform.WindowHandle) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwShowWindow(window);
}

pub fn windowPosition(handle: platform.WindowHandle) [2]i32 {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    var xpos: c_int = undefined;
    var ypos: c_int = undefined;
    c.glfwGetWindowPos(window, &xpos, &ypos);
    return .{ @intCast(xpos), @intCast(ypos) };
}

pub fn setWindowPosition(handle: platform.WindowHandle, position: [2]i32) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetWindowPos(window, @intCast(position[0]), @intCast(position[1]));
}

pub fn windowSize(handle: platform.WindowHandle) [2]u32 {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetWindowSize(window, &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn setWindowSize(handle: platform.WindowHandle, size: [2]u32) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetWindowSize(window, @intCast(size[0]), @intCast(size[1]));
}

pub fn windowFramebufferSize(handle: platform.WindowHandle) [2]u32 {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(window, &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn windowFocused(handle: platform.WindowHandle) bool {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    return c.glfwGetWindowAttrib(window, c.GLFW_FOCUSED) == c.GLFW_TRUE;
}

pub fn setWindowFocus(handle: platform.WindowHandle) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwFocusWindow(window);
}

pub fn windowHovered(handle: platform.WindowHandle) bool {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    return c.glfwGetWindowAttrib(window, c.GLFW_HOVERED) == c.GLFW_TRUE;
}

pub fn windowMinimized(handle: platform.WindowHandle) bool {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    return c.glfwGetWindowAttrib(window, c.GLFW_ICONIFIED) == c.GLFW_TRUE;
}

pub fn setWindowAlpha(handle: platform.WindowHandle, alpha: f32) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetWindowOpacity(window, alpha);
}

pub fn setWindowTitle(handle: platform.WindowHandle, title: []const u8) !void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetWindowTitle(window, try _arena.dupeZ(u8, title));
}

pub fn shouldCloseWindow(handle: platform.WindowHandle) bool {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    return c.glfwWindowShouldClose(window) == c.GLFW_TRUE;
}

pub fn cursorPosition(handle: platform.WindowHandle) [2]f32 {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    var xpos: f64 = undefined;
    var ypos: f64 = undefined;
    c.glfwGetCursorPos(window, &xpos, &ypos);
    return .{ @floatCast(xpos), @floatCast(ypos) };
}

pub fn cursorMode(handle: platform.WindowHandle) platform.CursorMode {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    const mode = c.glfwGetInputMode(window, c.GLFW_CURSOR);
    switch (mode) {
        c.GLFW_CURSOR_NORMAL => return .normal,
        c.GLFW_CURSOR_HIDDEN => return .hidden,
        c.GLFW_CURSOR_DISABLED => return .disabled,
        c.GLFW_CURSOR_CAPTURED => return .captured,
        else => return .normal,
    }
}

pub fn setCursor(handle: platform.WindowHandle, cursor_: platform.Cursor) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetCursor(window, _cursors[@intFromEnum(cursor_)]);
}

pub fn setCursorPosition(handle: platform.WindowHandle, position: [2]f32) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetCursorPos(window, @floatCast(position[0]), @floatCast(position[1]));
}

pub fn setCursorMode(handle: platform.WindowHandle, mode: platform.CursorMode) void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    const glfw_mode = switch (mode) {
        .normal => c.GLFW_CURSOR_NORMAL,
        .hidden => c.GLFW_CURSOR_HIDDEN,
        .disabled => c.GLFW_CURSOR_DISABLED,
        .captured => c.GLFW_CURSOR_CAPTURED,
    };
    c.glfwSetInputMode(window, c.GLFW_CURSOR, glfw_mode);
}

pub fn monitors() ![]platform.MonitorInfo {
    var monitor_count: c_int = undefined;
    const glfw_monitors = c.glfwGetMonitors(&monitor_count);
    if (monitor_count == 0) {
        return &[_]platform.MonitorInfo{};
    }

    const monitor_infos = try _arena.alloc(platform.MonitorInfo, @intCast(monitor_count));
    for (monitor_infos, 0..) |*monitor_info, i| {
        const glfw_monitor = glfw_monitors[i];

        var xpos: c_int = undefined;
        var ypos: c_int = undefined;
        c.glfwGetMonitorPos(glfw_monitor, &xpos, &ypos);

        const mode = c.glfwGetVideoMode(glfw_monitor);

        monitor_info.position = .{ @intCast(xpos), @intCast(ypos) };
        monitor_info.size = .{ @intCast(mode.*.width), @intCast(mode.*.height) };

        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetMonitorWorkarea(glfw_monitor, &xpos, &ypos, &width, &height);

        if (width > 0 and height > 0) {
            monitor_info.work_area = .{ @intCast(xpos), @intCast(ypos), @intCast(width), @intCast(height) };
        } else {
            monitor_info.work_area = .{
                monitor_info.position[0],
                monitor_info.position[1],
                monitor_info.size[0],
                monitor_info.size[1],
            };
        }

        var x_scale: f32 = undefined;
        var y_scale: f32 = undefined;
        c.glfwGetMonitorContentScale(glfw_monitor, &x_scale, &y_scale);
        monitor_info.scale = x_scale;
    }

    return monitor_infos;
}

pub fn clipboardText(handle: platform.WindowHandle) ?[]const u8 {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    const text = c.glfwGetClipboardString(window);
    if (text == null) {
        return null;
    }
    return text[0..std.mem.len(text)];
}

pub fn setClipboardText(handle: platform.WindowHandle, text: []const u8) !void {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
    c.glfwSetClipboardString(window, try _arena.dupeZ(u8, text));
}

pub fn pollEvents() void {
    _ = _arena_impl.reset(.retain_capacity);

    for (_windows_to_destroy.items) |handle| {
        const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
        c.glfwDestroyWindow(window);
    }
    _windows_to_destroy.clearRetainingCapacity();

    c.glfwPollEvents();
}

pub fn nativeWindowHandleType() platform.NativeWindowHandleType {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return .wayland;
    }

    return .default;
}
pub fn nativeWindowHandle(handle: platform.WindowHandle) ?*anyopaque {
    const window: ?*c.GLFWwindow = @ptrCast(@alignCast(handle.handle));
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
pub fn nativeDisplayHandle() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return c.glfwGetWaylandDisplay();
        return c.glfwGetX11Display();
    }
    return null;
}

pub fn registerWindowFocusCallback(callback: platform.WindowFocusCallback) anyerror!void {
    try _window_focus_callbacks.append(callback);
}

pub fn unregisterWindowFocusCallback(callback: platform.WindowFocusCallback) void {
    const index = std.mem.indexOf(
        platform.WindowFocusCallback,
        _window_focus_callbacks.items,
        &[_]platform.WindowFocusCallback{callback},
    );
    if (index != null) {
        _ = _window_focus_callbacks.swapRemove(index.?);
    }
}

pub fn registerCursorPositionCallback(callback: platform.CursorPositionCallback) anyerror!void {
    try _cursor_position_callbacks.append(callback);
}

pub fn unregisterCursorPositionCallback(callback: platform.CursorPositionCallback) void {
    const index = std.mem.indexOf(
        platform.CursorPositionCallback,
        _cursor_position_callbacks.items,
        &[_]platform.CursorPositionCallback{callback},
    );
    if (index != null) {
        _ = _cursor_position_callbacks.swapRemove(index.?);
    }
}

pub fn registerMouseButtonCallback(callback: platform.MouseButtonCallback) !void {
    try _mouse_button_callbacks.append(callback);
}

pub fn unregisterMouseButtonCallback(callback: platform.MouseButtonCallback) void {
    const index = std.mem.indexOf(
        platform.MouseButtonCallback,
        _mouse_button_callbacks.items,
        &[_]platform.MouseButtonCallback{callback},
    );
    if (index != null) {
        _ = _mouse_button_callbacks.swapRemove(index.?);
    }
}

pub fn registerMouseScrollCallback(callback: platform.MouseScrollCallback) !void {
    try _mouse_scroll_callbacks.append(callback);
}

pub fn unregisterMouseScrollCallback(callback: platform.MouseScrollCallback) void {
    const index = std.mem.indexOf(
        platform.MouseScrollCallback,
        _mouse_scroll_callbacks.items,
        &[_]platform.MouseScrollCallback{callback},
    );
    if (index != null) {
        _ = _mouse_scroll_callbacks.swapRemove(index.?);
    }
}

pub fn registerKeyCallback(callback: platform.KeyCallback) anyerror!void {
    try _key_callbacks.append(callback);
}

pub fn unregisterKeyCallback(callback: platform.KeyCallback) void {
    const index = std.mem.indexOf(
        platform.KeyCallback,
        _key_callbacks.items,
        &[_]platform.KeyCallback{callback},
    );
    if (index != null) {
        _ = _key_callbacks.swapRemove(index.?);
    }
}

pub fn registerCharCallback(callback: platform.CharCallback) anyerror!void {
    try _char_callbacks.append(callback);
}

pub fn unregisterCharCallback(callback: platform.CharCallback) void {
    const index = std.mem.indexOf(
        platform.CharCallback,
        _char_callbacks.items,
        &[_]platform.CharCallback{callback},
    );
    if (index != null) {
        _ = _char_callbacks.swapRemove(index.?);
    }
}

pub fn registerWindowCloseCallback(callback: platform.WindowCloseCallback) anyerror!void {
    try _window_close_callbacks.append(callback);
}

pub fn unregisterWindowCloseCallback(callback: platform.WindowCloseCallback) void {
    const index = std.mem.indexOf(
        platform.WindowCloseCallback,
        _window_close_callbacks.items,
        &[_]platform.WindowCloseCallback{callback},
    );
    if (index != null) {
        _ = _window_close_callbacks.swapRemove(index.?);
    }
}

pub fn registerWindowPositionCallback(callback: platform.WindowPositionCallback) anyerror!void {
    try _window_position_callbacks.append(callback);
}

pub fn unregisterWindowPositionCallback(callback: platform.WindowPositionCallback) void {
    const index = std.mem.indexOf(
        platform.WindowPositionCallback,
        _window_position_callbacks.items,
        &[_]platform.WindowPositionCallback{callback},
    );
    if (index != null) {
        _ = _window_position_callbacks.swapRemove(index.?);
    }
}

pub fn registerWindowSizeCallback(callback: platform.WindowSizeCallback) anyerror!void {
    try _window_size_callbacks.append(callback);
}

pub fn unregisterWindowSizeCallback(callback: platform.WindowSizeCallback) void {
    const index = std.mem.indexOf(
        platform.WindowSizeCallback,
        _window_size_callbacks.items,
        &[_]platform.WindowSizeCallback{callback},
    );
    if (index != null) {
        _ = _window_size_callbacks.swapRemove(index.?);
    }
}
