const std = @import("std");

const utils = @import("merlin_utils");

const glfw = @import("glfw.zig");
const noop = @import("noop.zig");

pub const log = std.log.scoped(.gfx);

pub const WindowHandle = packed struct { handle: *anyopaque };

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

const Type = enum {
    noop,
    glfw,
};

pub const Options = struct {
    type: Type,
};

pub const WindowOptions = struct {
    width: u32,
    height: u32,
    title: []const u8,
    visible: bool = true,
    focused: bool = true,
    decorated: bool = true,
    floating: bool = false,
};

pub const NativeWindowHandleType = enum(u8) {
    default, //  Platform default handle type (X11 on Linux).
    wayland,
};

pub const MonitorInfo = struct {
    position: [2]i32,
    size: [2]i32,
    work_area: [4]i32,
    scale: f32,
};

pub const MonitorEvent = enum(u8) {
    connected,
    disconnected,
};

pub const Cursor = enum(u8) {
    arrow,
    hand,
    text_input,
    resize_all,
    resize_ns,
    resize_ew,
    resize_nesw,
    resize_nwse,
    not_allowed,
};

pub const CursorMode = enum(u8) {
    normal,
    hidden,
    disabled,
    captured,
};

pub const MouseButton = enum(u8) {
    left,
    right,
    middle,
    button_4,
    button_5,
    button_6,
    button_7,
    button_8,
};

pub const Key = enum(u32) {
    space = 32,
    apostrophe = 39,
    comma = 44,
    minus = 45,
    period = 46,
    slash = 47,
    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,
    semicolon = 59,
    equal = 61,
    a = 65,
    b = 66,
    c = 67,
    d = 68,
    e = 69,
    f = 70,
    g = 71,
    h = 72,
    i = 73,
    j = 74,
    k = 75,
    l = 76,
    m = 77,
    n = 78,
    o = 79,
    p = 80,
    q = 81,
    r = 82,
    s = 83,
    t = 84,
    u = 85,
    v = 86,
    w = 87,
    x = 88,
    y = 89,
    z = 90,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    grave_accent = 96,
    world_1 = 161,
    world_2 = 162,
    escape = 256,
    enter = 257,
    tab = 258,
    backspace = 259,
    insert = 260,
    del = 261,
    right = 262,
    left = 263,
    down = 264,
    up = 265,
    page_up = 266,
    page_down = 267,
    home = 268,
    end = 269,
    caps_lock = 280,
    scroll_lock = 281,
    num_lock = 282,
    print_screen = 283,
    pause = 284,
    f1 = 290,
    f2 = 291,
    f3 = 292,
    f4 = 293,
    f5 = 294,
    f6 = 295,
    f7 = 296,
    f8 = 297,
    f9 = 298,
    f10 = 299,
    f11 = 300,
    f12 = 301,
    f13 = 302,
    f14 = 303,
    f15 = 304,
    f16 = 305,
    f17 = 306,
    f18 = 307,
    f19 = 308,
    f20 = 309,
    f21 = 310,
    f22 = 311,
    f23 = 312,
    f24 = 313,
    f25 = 314,
    numpad_0 = 320,
    numpad_1 = 321,
    numpad_2 = 322,
    numpad_3 = 323,
    numpad_4 = 324,
    numpad_5 = 325,
    numpad_6 = 326,
    numpad_7 = 327,
    numpad_8 = 328,
    numpad_9 = 329,
    numpad_decimal = 330,
    numpad_divide = 331,
    numpad_multiply = 332,
    numpad_subtract = 333,
    numpad_add = 334,
    numpad_enter = 335,
    numpad_equal = 336,
    left_shift = 340,
    left_control = 341,
    left_alt = 342,
    left_super = 343,
    right_shift = 344,
    right_control = 345,
    right_alt = 346,
    right_super = 347,
    menu = 348,
};

pub const KeyAction = enum(u8) {
    press,
    release,
    repeat,
};

pub const KeyModifier = packed struct {
    shift: bool,
    control: bool,
    alt: bool,
    super: bool,
    caps_lock: bool,
    num_lock: bool,
};

pub const MouseButtonAction = enum(u8) {
    press,
    release,
};

pub const WindowFocusCallback = *const fn (
    handle: WindowHandle,
    focused: bool,
) void;

pub const CursorPositionCallback = *const fn (
    handle: WindowHandle,
    position: [2]f32,
) void;

pub const MouseButtonCallback = *const fn (
    handle: WindowHandle,
    button: MouseButton,
    action: MouseButtonAction,
    modifiers: KeyModifier,
) void;

pub const MouseScrollCallback = *const fn (
    handle: WindowHandle,
    x_scroll: f32,
    y_scroll: f32,
) void;

pub const KeyCallback = *const fn (
    handle: WindowHandle,
    key: Key,
    scancode: i32,
    action: KeyAction,
    modifiers: KeyModifier,
) void;

pub const CharCallback = *const fn (
    handle: WindowHandle,
    codepoint: u32,
) void;

pub const WindowCloseCallback = *const fn (
    handle: WindowHandle,
) void;

pub const WindowPositionCallback = *const fn (
    handle: WindowHandle,
    position: [2]i32,
) void;

pub const WindowSizeCallback = *const fn (
    handle: WindowHandle,
    size: [2]u32,
) void;

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator) anyerror!void,
    deinit: *const fn () void,
    createWindow: *const fn (options: *const WindowOptions) anyerror!WindowHandle,
    destroyWindow: *const fn (handle: WindowHandle) void,
    showWindow: *const fn (handle: WindowHandle) void,
    windowPosition: *const fn (handle: WindowHandle) [2]i32,
    setWindowPosition: *const fn (handle: WindowHandle, position: [2]i32) void,
    windowSize: *const fn (handle: WindowHandle) [2]u32,
    setWindowSize: *const fn (handle: WindowHandle, size: [2]u32) void,
    windowFramebufferSize: *const fn (handle: WindowHandle) [2]u32,
    windowFocused: *const fn (handle: WindowHandle) bool,
    setWindowFocus: *const fn (handle: WindowHandle) void,
    windowHovered: *const fn (handle: WindowHandle) bool,
    windowMinimized: *const fn (handle: WindowHandle) bool,
    setWindowAlpha: *const fn (handle: WindowHandle, alpha: f32) void,
    setWindowTitle: *const fn (handle: WindowHandle, title: []const u8) anyerror!void,
    shouldCloseWindow: *const fn (handle: WindowHandle) bool,
    cursorPosition: *const fn (handle: WindowHandle) [2]f32,
    cursorMode: *const fn (handle: WindowHandle) CursorMode,
    setCursor: *const fn (handle: WindowHandle, cursor: Cursor) void,
    setCursorPosition: *const fn (handle: WindowHandle, position: [2]f32) void,
    setCursorMode: *const fn (handle: WindowHandle, mode: CursorMode) void,
    monitors: *const fn () anyerror![]MonitorInfo,
    clipboardText: *const fn (handle: WindowHandle) ?[]const u8,
    setClipboardText: *const fn (handle: WindowHandle, text: []const u8) anyerror!void,
    pollEvents: *const fn () void,
    nativeWindowHandleType: *const fn () NativeWindowHandleType,
    nativeWindowHandle: *const fn (handle: WindowHandle) ?*anyopaque,
    nativeDisplayHandle: *const fn () ?*anyopaque,
    registerWindowFocusCallback: *const fn (callback: WindowFocusCallback) anyerror!void,
    unregisterWindowFocusCallback: *const fn (callback: WindowFocusCallback) void,
    registerCursorPositionCallback: *const fn (callback: CursorPositionCallback) anyerror!void,
    unregisterCursorPositionCallback: *const fn (callback: CursorPositionCallback) void,
    registerMouseButtonCallback: *const fn (callback: MouseButtonCallback) anyerror!void,
    unregisterMouseButtonCallback: *const fn (callback: MouseButtonCallback) void,
    registerMouseScrollCallback: *const fn (callback: MouseScrollCallback) anyerror!void,
    unregisterMouseScrollCallback: *const fn (callback: MouseScrollCallback) void,
    registerKeyCallback: *const fn (callback: KeyCallback) anyerror!void,
    unregisterKeyCallback: *const fn (callback: KeyCallback) void,
    registerCharCallback: *const fn (callback: CharCallback) anyerror!void,
    unregisterCharCallback: *const fn (callback: CharCallback) void,
    registerWindowCloseCallback: *const fn (callback: WindowCloseCallback) anyerror!void,
    unregisterWindowCloseCallback: *const fn (callback: WindowCloseCallback) void,
    registerWindowPositionCallback: *const fn (callback: WindowPositionCallback) anyerror!void,
    unregisterWindowPositionCallback: *const fn (callback: WindowPositionCallback) void,
    registerWindowSizeCallback: *const fn (callback: WindowSizeCallback) anyerror!void,
    unregisterWindowSizeCallback: *const fn (callback: WindowSizeCallback) void,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _v_tab: VTab = undefined;

fn getVTab(
    platform_type: Type,
) !VTab {
    switch (platform_type) {
        Type.noop => return VTab{
            .init = noop.init,
            .deinit = noop.deinit,
            .createWindow = noop.createWindow,
            .destroyWindow = noop.destroyWindow,
            .showWindow = noop.showWindow,
            .windowPosition = noop.windowPosition,
            .setWindowPosition = noop.setWindowPosition,
            .windowSize = noop.windowSize,
            .setWindowSize = noop.setWindowSize,
            .windowFramebufferSize = noop.windowFramebufferSize,
            .windowFocused = noop.windowFocused,
            .setWindowFocus = noop.setWindowFocus,
            .windowHovered = noop.windowHovered,
            .windowMinimized = noop.windowMinimized,
            .setWindowAlpha = noop.setWindowAlpha,
            .setWindowTitle = noop.setWindowTitle,
            .shouldCloseWindow = noop.shouldCloseWindow,
            .cursorPosition = noop.cursorPosition,
            .cursorMode = noop.cursorMode,
            .setCursor = noop.setCursor,
            .setCursorPosition = noop.setCursorPosition,
            .setCursorMode = noop.setCursorMode,
            .monitors = noop.monitors,
            .clipboardText = noop.clipboardText,
            .setClipboardText = noop.setClipboardText,
            .pollEvents = noop.pollEvents,
            .nativeWindowHandleType = noop.nativeWindowHandleType,
            .nativeWindowHandle = noop.nativeWindowHandle,
            .nativeDisplayHandle = noop.nativeDisplayHandle,
            .registerWindowFocusCallback = noop.registerWindowFocusCallback,
            .unregisterWindowFocusCallback = noop.unregisterWindowFocusCallback,
            .registerCursorPositionCallback = noop.registerCursorPositionCallback,
            .unregisterCursorPositionCallback = noop.unregisterCursorPositionCallback,
            .registerMouseButtonCallback = noop.registerMouseButtonCallback,
            .unregisterMouseButtonCallback = noop.unregisterMouseButtonCallback,
            .registerMouseScrollCallback = noop.registerMouseScrollCallback,
            .unregisterMouseScrollCallback = noop.unregisterMouseScrollCallback,
            .registerKeyCallback = noop.registerKeyCallback,
            .unregisterKeyCallback = noop.unregisterKeyCallback,
            .registerCharCallback = noop.registerCharCallback,
            .unregisterCharCallback = noop.unregisterCharCallback,
            .registerWindowCloseCallback = noop.registerWindowCloseCallback,
            .unregisterWindowCloseCallback = noop.unregisterWindowCloseCallback,
            .registerWindowPositionCallback = noop.registerWindowPositionCallback,
            .unregisterWindowPositionCallback = noop.unregisterWindowPositionCallback,
            .registerWindowSizeCallback = noop.registerWindowSizeCallback,
            .unregisterWindowSizeCallback = noop.unregisterWindowSizeCallback,
        },
        Type.glfw => return VTab{
            .init = glfw.init,
            .deinit = glfw.deinit,
            .createWindow = glfw.createWindow,
            .destroyWindow = glfw.destroyWindow,
            .showWindow = glfw.showWindow,
            .windowPosition = glfw.windowPosition,
            .setWindowPosition = glfw.setWindowPosition,
            .windowSize = glfw.windowSize,
            .setWindowSize = glfw.setWindowSize,
            .windowFramebufferSize = glfw.windowFramebufferSize,
            .windowFocused = glfw.windowFocused,
            .setWindowFocus = glfw.setWindowFocus,
            .windowHovered = glfw.windowHovered,
            .windowMinimized = glfw.windowMinimized,
            .setWindowAlpha = glfw.setWindowAlpha,
            .setWindowTitle = glfw.setWindowTitle,
            .shouldCloseWindow = glfw.shouldCloseWindow,
            .cursorPosition = glfw.cursorPosition,
            .cursorMode = glfw.cursorMode,
            .setCursor = glfw.setCursor,
            .setCursorPosition = glfw.setCursorPosition,
            .setCursorMode = glfw.setCursorMode,
            .monitors = glfw.monitors,
            .clipboardText = glfw.clipboardText,
            .setClipboardText = glfw.setClipboardText,
            .pollEvents = glfw.pollEvents,
            .nativeWindowHandleType = glfw.nativeWindowHandleType,
            .nativeWindowHandle = glfw.nativeWindowHandle,
            .nativeDisplayHandle = glfw.nativeDisplayHandle,
            .registerWindowFocusCallback = glfw.registerWindowFocusCallback,
            .unregisterWindowFocusCallback = glfw.unregisterWindowFocusCallback,
            .registerCursorPositionCallback = glfw.registerCursorPositionCallback,
            .unregisterCursorPositionCallback = glfw.unregisterCursorPositionCallback,
            .registerMouseButtonCallback = glfw.registerMouseButtonCallback,
            .unregisterMouseButtonCallback = glfw.unregisterMouseButtonCallback,
            .registerMouseScrollCallback = glfw.registerMouseScrollCallback,
            .unregisterMouseScrollCallback = glfw.unregisterMouseScrollCallback,
            .registerKeyCallback = glfw.registerKeyCallback,
            .unregisterKeyCallback = glfw.unregisterKeyCallback,
            .registerCharCallback = glfw.registerCharCallback,
            .unregisterCharCallback = glfw.unregisterCharCallback,
            .registerWindowCloseCallback = glfw.registerWindowCloseCallback,
            .unregisterWindowCloseCallback = glfw.unregisterWindowCloseCallback,
            .registerWindowPositionCallback = glfw.registerWindowPositionCallback,
            .unregisterWindowPositionCallback = glfw.unregisterWindowPositionCallback,
            .registerWindowSizeCallback = glfw.registerWindowSizeCallback,
            .unregisterWindowSizeCallback = glfw.unregisterWindowSizeCallback,
        },
    }
}

pub fn init(
    allocator: std.mem.Allocator,
    options: Options,
) !void {
    log.debug("Initializing platform", .{});

    _v_tab = try getVTab(options.type);

    try _v_tab.init(allocator);
    errdefer _v_tab.deinit();
}

pub fn deinit() void {
    log.debug("Deinitializing platform", .{});

    _v_tab.deinit();
}

pub inline fn createWindow(options: WindowOptions) !WindowHandle {
    return _v_tab.createWindow(&options);
}

pub inline fn destroyWindow(handle: WindowHandle) void {
    _v_tab.destroyWindow(handle);
}

pub inline fn showWindow(handle: WindowHandle) void {
    _v_tab.showWindow(handle);
}

pub inline fn windowPosition(handle: WindowHandle) [2]i32 {
    return _v_tab.windowPosition(handle);
}

pub inline fn setWindowPosition(handle: WindowHandle, position: [2]i32) void {
    _v_tab.setWindowPosition(handle, position);
}

pub inline fn windowSize(handle: WindowHandle) [2]u32 {
    return _v_tab.windowSize(handle);
}

pub inline fn setWindowSize(handle: WindowHandle, size: [2]u32) void {
    _v_tab.setWindowSize(handle, size);
}

pub inline fn windowFramebufferSize(handle: WindowHandle) [2]u32 {
    return _v_tab.windowFramebufferSize(handle);
}

pub inline fn windowFocused(handle: WindowHandle) bool {
    return _v_tab.windowFocused(handle);
}

pub inline fn setWindowFocus(handle: WindowHandle) void {
    _v_tab.setWindowFocus(handle);
}

pub inline fn windowHovered(handle: WindowHandle) bool {
    return _v_tab.windowHovered(handle);
}

pub inline fn windowMinimized(handle: WindowHandle) bool {
    return _v_tab.windowMinimized(handle);
}

pub inline fn setWindowAlpha(handle: WindowHandle, alpha: f32) void {
    _v_tab.setWindowAlpha(handle, alpha);
}

pub inline fn setWindowTitle(handle: WindowHandle, title: []const u8) !void {
    return _v_tab.setWindowTitle(handle, title);
}

pub inline fn shouldCloseWindow(handle: WindowHandle) bool {
    return _v_tab.shouldCloseWindow(handle);
}

pub inline fn cursorPosition(handle: WindowHandle) [2]f32 {
    return _v_tab.cursorPosition(handle);
}

pub inline fn cursorMode(handle: WindowHandle) CursorMode {
    return _v_tab.cursorMode(handle);
}

pub inline fn setCursor(handle: WindowHandle, cursor_: Cursor) void {
    _v_tab.setCursor(handle, cursor_);
}

pub inline fn setCursorPosition(handle: WindowHandle, position: [2]f32) void {
    _v_tab.setCursorPosition(handle, position);
}

pub inline fn setCursorMode(handle: WindowHandle, mode: CursorMode) void {
    _v_tab.setCursorMode(handle, mode);
}

pub inline fn monitors() ![]MonitorInfo {
    return _v_tab.monitors();
}

pub inline fn clipboardText(handle: WindowHandle) ?[]const u8 {
    return _v_tab.clipboardText(handle);
}

pub inline fn setClipboardText(handle: WindowHandle, text: []const u8) !void {
    return _v_tab.setClipboardText(handle, text);
}

pub inline fn pollEvents() void {
    _v_tab.pollEvents();
}

pub inline fn nativeWindowHandleType() NativeWindowHandleType {
    return _v_tab.nativeWindowHandleType();
}

pub inline fn nativeWindowHandle(handle: WindowHandle) ?*anyopaque {
    return _v_tab.nativeWindowHandle(handle);
}

pub inline fn nativeDisplayHandle() ?*anyopaque {
    return _v_tab.nativeDisplayHandle();
}

pub inline fn registerWindowFocusCallback(callback: WindowFocusCallback) !void {
    try _v_tab.registerWindowFocusCallback(callback);
}

pub inline fn unregisterWindowFocusCallback(callback: WindowFocusCallback) void {
    _v_tab.unregisterWindowFocusCallback(callback);
}

pub inline fn registerCursorPositionCallback(callback: CursorPositionCallback) !void {
    try _v_tab.registerCursorPositionCallback(callback);
}

pub inline fn unregisterCursorPositionCallback(callback: CursorPositionCallback) void {
    _v_tab.unregisterCursorPositionCallback(callback);
}

pub inline fn registerMouseButtonCallback(callback: MouseButtonCallback) !void {
    try _v_tab.registerMouseButtonCallback(callback);
}

pub inline fn unregisterMouseButtonCallback(callback: MouseButtonCallback) void {
    _v_tab.unregisterMouseButtonCallback(callback);
}

pub inline fn registerMouseScrollCallback(callback: MouseScrollCallback) !void {
    try _v_tab.registerMouseScrollCallback(callback);
}

pub inline fn unregisterMouseScrollCallback(callback: MouseScrollCallback) void {
    _v_tab.unregisterMouseScrollCallback(callback);
}

pub inline fn registerKeyCallback(callback: KeyCallback) !void {
    try _v_tab.registerKeyCallback(callback);
}

pub inline fn unregisterKeyCallback(callback: KeyCallback) void {
    _v_tab.unregisterKeyCallback(callback);
}

pub inline fn registerCharCallback(callback: CharCallback) !void {
    try _v_tab.registerCharCallback(callback);
}

pub inline fn unregisterCharCallback(callback: CharCallback) void {
    _v_tab.unregisterCharCallback(callback);
}

pub inline fn registerWindowCloseCallback(callback: WindowCloseCallback) !void {
    try _v_tab.registerWindowCloseCallback(callback);
}

pub inline fn unregisterWindowCloseCallback(callback: WindowCloseCallback) void {
    _v_tab.unregisterWindowCloseCallback(callback);
}

pub inline fn registerWindowPositionCallback(callback: WindowPositionCallback) !void {
    try _v_tab.registerWindowPositionCallback(callback);
}

pub inline fn unregisterWindowPositionCallback(callback: WindowPositionCallback) void {
    _v_tab.unregisterWindowPositionCallback(callback);
}

pub inline fn registerWindowSizeCallback(callback: WindowSizeCallback) !void {
    try _v_tab.registerWindowSizeCallback(callback);
}

pub inline fn unregisterWindowSizeCallback(callback: WindowSizeCallback) void {
    _v_tab.unregisterWindowSizeCallback(callback);
}
