const std = @import("std");

const platform = @import("platform.zig");

pub fn init() !void {}
pub fn deinit() void {}
pub fn createWindow(_: platform.WindowHandle, _: *const platform.WindowOptions) !void {}
pub fn destroyWindow(_: platform.WindowHandle) void {}
pub fn shouldCloseWindow(_: platform.WindowHandle) bool {
    return true;
}
pub fn pollEvents() void {}
