const std = @import("std");

const platform = @import("platform.zig");

pub fn init(_: std.mem.Allocator) !void {}
pub fn deinit() void {}
pub fn createWindow(_: *const platform.WindowOptions) !platform.WindowHandle {
    return .{ .handle = undefined };
}
pub fn destroyWindow(_: platform.WindowHandle) void {}
pub fn showWindow(_: platform.WindowHandle) void {}
pub fn windowPosition(_: platform.WindowHandle) [2]i32 {
    return .{ 0, 0 };
}
pub fn setWindowPosition(_: platform.WindowHandle, _: [2]i32) void {}
pub fn windowSize(_: platform.WindowHandle) [2]u32 {
    return .{ 0, 0 };
}
pub fn setWindowSize(_: platform.WindowHandle, _: [2]u32) void {}
pub fn windowFramebufferSize(_: platform.WindowHandle) [2]u32 {
    return .{ 0, 0 };
}
pub fn windowFocused(_: platform.WindowHandle) bool {
    return false;
}
pub fn setWindowFocus(_: platform.WindowHandle) void {}
pub fn windowHovered(_: platform.WindowHandle) bool {
    return false;
}
pub fn windowMinimized(_: platform.WindowHandle) bool {
    return false;
}
pub fn setWindowAlpha(_: platform.WindowHandle, _: f32) void {}
pub fn setWindowTitle(_: platform.WindowHandle, _: []const u8) !void {}
pub fn shouldCloseWindow(_: platform.WindowHandle) bool {
    return true;
}
//pub fn cursor(_: platform.WindowHandle) platform.Cursor {
//    return .arrow;
//}
pub fn cursorPosition(_: platform.WindowHandle) [2]f32 {
    return .{ 0, 0 };
}
pub fn cursorMode(_: platform.WindowHandle) platform.CursorMode {
    return .normal;
}
pub fn setCursor(_: platform.WindowHandle, _: platform.Cursor) void {}
pub fn setCursorPosition(_: platform.WindowHandle, _: [2]f32) void {}
pub fn setCursorMode(_: platform.WindowHandle, _: platform.CursorMode) void {}
pub fn monitors() ![]platform.MonitorInfo {
    return &[_]platform.MonitorInfo{};
}
pub fn clipboardText(_: platform.WindowHandle) ?[]const u8 {
    return null;
}
pub fn setClipboardText(_: platform.WindowHandle, _: []const u8) !void {}
pub fn pollEvents() void {}
pub fn nativeWindowHandleType() platform.NativeWindowHandleType {
    return .default;
}
pub fn nativeWindowHandle(_: platform.WindowHandle) ?*anyopaque {
    return undefined;
}
pub fn nativeDisplayHandle() ?*anyopaque {
    return null;
}
pub fn registerWindowFocusCallback(_: platform.WindowFocusCallback) anyerror!void {}
pub fn unregisterWindowFocusCallback(_: platform.WindowFocusCallback) void {}
pub fn registerCursorPositionCallback(_: platform.CursorPositionCallback) anyerror!void {}
pub fn unregisterCursorPositionCallback(_: platform.CursorPositionCallback) void {}
pub fn registerMouseButtonCallback(_: platform.MouseButtonCallback) anyerror!void {}
pub fn unregisterMouseButtonCallback(_: platform.MouseButtonCallback) void {}
pub fn registerMouseScrollCallback(_: platform.MouseScrollCallback) anyerror!void {}
pub fn unregisterMouseScrollCallback(_: platform.MouseScrollCallback) void {}
pub fn registerKeyCallback(_: platform.KeyCallback) anyerror!void {}
pub fn unregisterKeyCallback(_: platform.KeyCallback) void {}
pub fn registerCharCallback(_: platform.CharCallback) anyerror!void {}
pub fn unregisterCharCallback(_: platform.CharCallback) void {}
pub fn registerWindowCloseCallback(_: platform.WindowCloseCallback) anyerror!void {}
pub fn unregisterWindowCloseCallback(_: platform.WindowCloseCallback) void {}
pub fn registerWindowPositionCallback(_: platform.WindowPositionCallback) anyerror!void {}
pub fn unregisterWindowPositionCallback(_: platform.WindowPositionCallback) void {}
pub fn registerWindowSizeCallback(_: platform.WindowSizeCallback) anyerror!void {}
pub fn unregisterWindowSizeCallback(_: platform.WindowSizeCallback) void {}
