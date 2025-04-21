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

var cursors: [@typeInfo(platform.Cursor).@"enum".fields.len]?*c.GLFWcursor = undefined;

var window_focus_callbacks: std.ArrayList(platform.WindowFocusCallback) = undefined;
var cursor_position_callbacks: std.ArrayList(platform.CursorPositionCallback) = undefined;
var mouse_button_callbacks: std.ArrayList(platform.MouseButtonCallback) = undefined;
var mouse_scroll_callbacks: std.ArrayList(platform.MouseScrollCallback) = undefined;
var key_callbacks: std.ArrayList(platform.KeyCallback) = undefined;
var char_callbacks: std.ArrayList(platform.CharCallback) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    log.err("{s}", .{description});
}

fn glfwWindowFocusCallback(
    window: ?*c.GLFWwindow,
    focused: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = @enumFromInt(@intFromPtr(c.glfwGetWindowUserPointer(window)));
    const focused_ = focused == c.GLFW_TRUE;

    for (window_focus_callbacks.items) |callback| {
        callback(handle, focused_);
    }
}

fn glfwCursorPositionCallback(
    window: ?*c.GLFWwindow,
    xpos: f64,
    ypos: f64,
) callconv(.c) void {
    const handle: platform.WindowHandle = @enumFromInt(@intFromPtr(c.glfwGetWindowUserPointer(window)));

    for (cursor_position_callbacks.items) |callback| {
        callback(handle, .{ @floatCast(xpos), @floatCast(ypos) });
    }
}

fn glfwMouseButtonCallback(
    window: ?*c.GLFWwindow,
    button: c_int,
    action: c_int,
    _: c_int,
) callconv(.c) void {
    const handle: platform.WindowHandle = @enumFromInt(@intFromPtr(c.glfwGetWindowUserPointer(window)));
    const button_: platform.MouseButton = @enumFromInt(button);
    const action_ = switch (action) {
        c.GLFW_PRESS => platform.MouseButtonAction.press,
        c.GLFW_RELEASE => platform.MouseButtonAction.release,
        else => return,
    };

    for (mouse_button_callbacks.items) |callback| {
        callback(handle, button_, action_);
    }
}

fn glfwMouseScrollCallback(
    window: ?*c.GLFWwindow,
    x_scroll: f64,
    y_scroll: f64,
) callconv(.c) void {
    const handle: platform.WindowHandle = @enumFromInt(@intFromPtr(c.glfwGetWindowUserPointer(window)));

    for (mouse_scroll_callbacks.items) |callback| {
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
    const handle: platform.WindowHandle = @enumFromInt(@intFromPtr(c.glfwGetWindowUserPointer(window)));
    //const key_ = @enumFromInt(key);
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

    const modifiers = platform.KeyModifier{
        .shift = (mod & c.GLFW_MOD_SHIFT) != 0,
        .control = (mod & c.GLFW_MOD_CONTROL) != 0,
        .alt = (mod & c.GLFW_MOD_ALT) != 0,
        .super = (mod & c.GLFW_MOD_SUPER) != 0,
        .caps_lock = (mod & c.GLFW_MOD_CAPS_LOCK) != 0,
        .num_lock = (mod & c.GLFW_MOD_NUM_LOCK) != 0,
    };

    for (key_callbacks.items) |callback| {
        callback(handle, key_, scancode, action_, modifiers);
    }
}

fn glfwCharCallback(
    window: ?*c.GLFWwindow,
    codepoint: c_uint,
) callconv(.c) void {
    const handle: platform.WindowHandle = @enumFromInt(@intFromPtr(c.glfwGetWindowUserPointer(window)));

    for (char_callbacks.items) |callback| {
        callback(handle, codepoint);
    }
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

    window_focus_callbacks = .init(gpa);
    errdefer window_focus_callbacks.deinit();

    cursor_position_callbacks = .init(gpa);
    errdefer cursor_position_callbacks.deinit();

    mouse_button_callbacks = .init(gpa);
    errdefer mouse_button_callbacks.deinit();

    mouse_scroll_callbacks = .init(gpa);
    errdefer mouse_scroll_callbacks.deinit();

    key_callbacks = .init(gpa);
    errdefer key_callbacks.deinit();

    char_callbacks = .init(gpa);
    errdefer char_callbacks.deinit();

    _ = c.glfwSetErrorCallback(&glfwErrorCallback);

    //c.glfwInitHint(c.GLFW_PLATFORM, c.GLFW_PLATFORM_X11);

    if (c.glfwInit() != c.GLFW_TRUE) {
        log.err("Failed to initialize GLFW", .{});
        return error.GlfwInitFailed;
    }
    errdefer c.glfwTerminate();

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);

    cursors = .{
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
    for (cursors) |cursor_| {
        c.glfwDestroyCursor(cursor_);
    }

    char_callbacks.deinit();
    key_callbacks.deinit();
    mouse_scroll_callbacks.deinit();
    mouse_button_callbacks.deinit();
    cursor_position_callbacks.deinit();
    window_focus_callbacks.deinit();

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

    c.glfwSetWindowUserPointer(window, @ptrFromInt(@intFromEnum(handle)));

    _ = c.glfwSetWindowFocusCallback(window, &glfwWindowFocusCallback);
    _ = c.glfwSetCursorPosCallback(window, &glfwCursorPositionCallback);
    _ = c.glfwSetMouseButtonCallback(window, &glfwMouseButtonCallback);
    _ = c.glfwSetScrollCallback(window, &glfwMouseScrollCallback);
    _ = c.glfwSetKeyCallback(window, &glfwKeyCallback);
    _ = c.glfwSetCharCallback(window, &glfwCharCallback);
}

pub fn destroyWindow(handle: platform.WindowHandle) void {
    c.glfwDestroyWindow(windows.value(handle));
}

pub fn windowPosition(handle: platform.WindowHandle) [2]i32 {
    var xpos: c_int = undefined;
    var ypos: c_int = undefined;
    c.glfwGetWindowPos(windows.value(handle), &xpos, &ypos);
    return .{ @intCast(xpos), @intCast(ypos) };
}

pub fn windowSize(handle: platform.WindowHandle) [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetWindowSize(windows.value(handle), &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn windowFramebufferSize(handle: platform.WindowHandle) [2]u32 {
    var width: c_int = undefined;
    var height: c_int = undefined;
    c.glfwGetFramebufferSize(windows.value(handle), &width, &height);
    return .{ @intCast(width), @intCast(height) };
}

pub fn windowFocused(handle: platform.WindowHandle) bool {
    return c.glfwGetWindowAttrib(windows.value(handle), c.GLFW_FOCUSED) == c.GLFW_TRUE;
}

pub fn windowHovered(handle: platform.WindowHandle) bool {
    return c.glfwGetWindowAttrib(windows.value(handle), c.GLFW_HOVERED) == c.GLFW_TRUE;
}

pub fn shouldCloseWindow(handle: platform.WindowHandle) bool {
    return c.glfwWindowShouldClose(windows.value(handle)) == c.GLFW_TRUE;
}

pub fn cursorPosition(handle: platform.WindowHandle) [2]f32 {
    var xpos: f64 = undefined;
    var ypos: f64 = undefined;
    c.glfwGetCursorPos(windows.value(handle), &xpos, &ypos);
    return .{ @floatCast(xpos), @floatCast(ypos) };
}

pub fn cursorMode(handle: platform.WindowHandle) platform.CursorMode {
    const mode = c.glfwGetInputMode(windows.value(handle), c.GLFW_CURSOR);
    switch (mode) {
        c.GLFW_CURSOR_NORMAL => return .normal,
        c.GLFW_CURSOR_HIDDEN => return .hidden,
        c.GLFW_CURSOR_DISABLED => return .disabled,
        c.GLFW_CURSOR_CAPTURED => return .captured,
        else => return .normal,
    }
}

pub fn setCursor(handle: platform.WindowHandle, cursor_: platform.Cursor) void {
    c.glfwSetCursor(windows.value(handle), cursors[@intFromEnum(cursor_)]);
}

pub fn setCursorPosition(handle: platform.WindowHandle, position: [2]f32) void {
    c.glfwSetCursorPos(windows.value(handle), @floatCast(position[0]), @floatCast(position[1]));
}

pub fn setCursorMode(handle: platform.WindowHandle, mode: platform.CursorMode) void {
    const glfw_mode = switch (mode) {
        .normal => c.GLFW_CURSOR_NORMAL,
        .hidden => c.GLFW_CURSOR_HIDDEN,
        .disabled => c.GLFW_CURSOR_DISABLED,
        .captured => c.GLFW_CURSOR_CAPTURED,
    };
    c.glfwSetInputMode(windows.value(handle), c.GLFW_CURSOR, glfw_mode);
}

pub fn monitors() ![]platform.MonitorInfo {
    var monitor_count: c_int = undefined;
    const glfw_monitors = c.glfwGetMonitors(&monitor_count);
    if (monitor_count == 0) {
        return &[_]platform.MonitorInfo{};
    }

    const monitor_infos = try arena.alloc(platform.MonitorInfo, @intCast(monitor_count));
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

pub fn pollEvents() void {
    _ = arena_impl.reset(.retain_capacity);

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
pub fn nativeDisplayHandle() ?*anyopaque {
    if (builtin.os.tag == .linux) {
        if (c.glfwGetPlatform() == c.GLFW_PLATFORM_WAYLAND)
            return c.glfwGetWaylandDisplay();
        return c.glfwGetX11Display();
    }
    return null;
}

pub fn registerWindowFocusCallback(callback: platform.WindowFocusCallback) anyerror!void {
    try window_focus_callbacks.append(callback);
}

pub fn unregisterWindowFocusCallback(callback: platform.WindowFocusCallback) void {
    const index = std.mem.indexOf(
        platform.WindowFocusCallback,
        window_focus_callbacks.items,
        &[_]platform.WindowFocusCallback{callback},
    );
    if (index != null) {
        _ = window_focus_callbacks.swapRemove(index.?);
    }
}

pub fn registerCursorPositionCallback(callback: platform.CursorPositionCallback) anyerror!void {
    try cursor_position_callbacks.append(callback);
}

pub fn unregisterCursorPositionCallback(callback: platform.CursorPositionCallback) void {
    const index = std.mem.indexOf(
        platform.CursorPositionCallback,
        cursor_position_callbacks.items,
        &[_]platform.CursorPositionCallback{callback},
    );
    if (index != null) {
        _ = cursor_position_callbacks.swapRemove(index.?);
    }
}

pub fn registerMouseButtonCallback(callback: platform.MouseButtonCallback) !void {
    try mouse_button_callbacks.append(callback);
}

pub fn unregisterMouseButtonCallback(callback: platform.MouseButtonCallback) void {
    const index = std.mem.indexOf(
        platform.MouseButtonCallback,
        mouse_button_callbacks.items,
        &[_]platform.MouseButtonCallback{callback},
    );
    if (index != null) {
        _ = mouse_button_callbacks.swapRemove(index.?);
    }
}

pub fn registerMouseScrollCallback(callback: platform.MouseScrollCallback) !void {
    try mouse_scroll_callbacks.append(callback);
}

pub fn unregisterMouseScrollCallback(callback: platform.MouseScrollCallback) void {
    const index = std.mem.indexOf(
        platform.MouseScrollCallback,
        mouse_scroll_callbacks.items,
        &[_]platform.MouseScrollCallback{callback},
    );
    if (index != null) {
        _ = mouse_scroll_callbacks.swapRemove(index.?);
    }
}

pub fn registerKeyCallback(callback: platform.KeyCallback) anyerror!void {
    try key_callbacks.append(callback);
}

pub fn unregisterKeyCallback(callback: platform.KeyCallback) void {
    const index = std.mem.indexOf(
        platform.KeyCallback,
        key_callbacks.items,
        &[_]platform.KeyCallback{callback},
    );
    if (index != null) {
        _ = key_callbacks.swapRemove(index.?);
    }
}

pub fn registerCharCallback(callback: platform.CharCallback) anyerror!void {
    try char_callbacks.append(callback);
}

pub fn unregisterCharCallback(callback: platform.CharCallback) void {
    const index = std.mem.indexOf(
        platform.CharCallback,
        char_callbacks.items,
        &[_]platform.CharCallback{callback},
    );
    if (index != null) {
        _ = char_callbacks.swapRemove(index.?);
    }
}
