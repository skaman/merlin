const std = @import("std");

const platform = @import("platform.zig");

pub fn init(_: std.mem.Allocator, _: std.mem.Allocator, _: *const platform.Options) !void {}
pub fn deinit() void {}
pub fn createWindow(_: platform.WindowHandle, _: *const platform.WindowOptions) !void {}
pub fn destroyWindow(_: platform.WindowHandle) void {}
pub fn shouldCloseDefaultWindow() bool {
    return true;
}
pub fn shouldCloseWindow(_: platform.WindowHandle) bool {
    return true;
}
pub fn pollEvents() void {}
