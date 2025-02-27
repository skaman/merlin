const std = @import("std");

const platform = @import("platform.zig");

pub fn init(_: std.mem.Allocator, _: std.mem.Allocator) !void {}
pub fn deinit() void {}
pub fn createWindow(_: platform.WindowHandle, _: *const platform.WindowOptions) !void {}
pub fn destroyWindow(_: platform.WindowHandle) void {}
pub fn getWindowFramebufferSize(_: platform.WindowHandle) [2]u32 {
    return .{ 0, 0 };
}
pub fn shouldCloseWindow(_: platform.WindowHandle) bool {
    return true;
}
pub fn pollEvents() void {}
pub fn getNativeWindowHandleType() platform.NativeWindowHandleType {
    return .default;
}
pub fn getNativeWindowHandle(_: platform.WindowHandle) ?*anyopaque {
    return undefined;
}
pub fn getNativeDisplayHandle() ?*anyopaque {
    return null;
}
