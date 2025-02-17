const std = @import("std");

const z3dfx = @import("z3dfx.zig");

pub const NoopRenderer = struct {
    pub fn deinit(_: *const NoopRenderer) void {}
    pub fn getSwapchainSize(_: *const NoopRenderer) z3dfx.Size {
        return .{ .width = 0, .height = 0 };
    }
    pub fn createShader(_: *const NoopRenderer, _: z3dfx.ShaderHandle, _: []const u8) !void {}
    pub fn destroyShader(_: *const NoopRenderer, _: z3dfx.ShaderHandle) void {}
    pub fn createProgram(_: *const NoopRenderer, _: z3dfx.ProgramHandle, _: z3dfx.ShaderHandle, _: z3dfx.ShaderHandle) !void {}
    pub fn destroyProgram(_: *const NoopRenderer, _: z3dfx.ProgramHandle) void {}
    pub fn beginFrame(_: *const NoopRenderer) !void {}
    pub fn endFrame(_: *const NoopRenderer) !void {}
    pub fn setViewport(_: *const NoopRenderer, _: z3dfx.Rect) void {}
    pub fn setScissor(_: *const NoopRenderer, _: z3dfx.Rect) void {}
    pub fn bindProgram(_: *const NoopRenderer, _: z3dfx.ProgramHandle) void {}
    pub fn draw(_: *const NoopRenderer, _: u32, _: u32, _: u32, _: u32) void {}
};
