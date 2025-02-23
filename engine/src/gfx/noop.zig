const std = @import("std");

const shared = @import("shared");

const gfx = @import("gfx.zig");

pub const NoopRenderer = struct {
    pub fn deinit(_: *const NoopRenderer) void {}
    pub fn getSwapchainSize(_: *const NoopRenderer) gfx.Size {
        return .{ .width = 0, .height = 0 };
    }
    pub fn invalidateFramebuffer(_: *const NoopRenderer) void {}
    pub fn createShader(_: *const NoopRenderer, _: gfx.ShaderHandle, _: *const shared.ShaderData) !void {}
    pub fn destroyShader(_: *const NoopRenderer, _: gfx.ShaderHandle) void {}
    pub fn createProgram(_: *const NoopRenderer, _: gfx.ProgramHandle, _: gfx.ShaderHandle, _: gfx.ShaderHandle) !void {}
    pub fn destroyProgram(_: *const NoopRenderer, _: gfx.ProgramHandle) void {}
    pub fn createVertexBuffer(_: *const NoopRenderer, _: gfx.VertexBufferHandle, _: [*]const u8, _: u32, _: shared.VertexLayout) !void {}
    pub fn destroyVertexBuffer(_: *const NoopRenderer, _: gfx.VertexBufferHandle) void {}
    pub fn beginFrame(_: *const NoopRenderer) !bool {
        return true;
    }
    pub fn endFrame(_: *const NoopRenderer) !void {}
    pub fn setViewport(_: *const NoopRenderer, _: gfx.Rect) void {}
    pub fn setScissor(_: *const NoopRenderer, _: gfx.Rect) void {}
    pub fn bindProgram(_: *const NoopRenderer, _: gfx.ProgramHandle) void {}
    pub fn bindVertexBuffer(_: *const NoopRenderer, _: gfx.VertexBufferHandle) void {}
    pub fn draw(_: *const NoopRenderer, _: u32, _: u32, _: u32, _: u32) void {}
};
