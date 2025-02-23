const std = @import("std");

const shared = @import("shared");

const gfx = @import("gfx.zig");

pub fn init(_: *const gfx.GraphicsContext) !void {}
pub fn deinit() void {}
pub fn getSwapchainSize() gfx.Size {
    return .{ .width = 0, .height = 0 };
}
pub fn invalidateFramebuffer() void {}
pub fn createShader(_: gfx.ShaderHandle, _: *const shared.ShaderData) !void {}
pub fn destroyShader(_: gfx.ShaderHandle) void {}
pub fn createProgram(_: gfx.ProgramHandle, _: gfx.ShaderHandle, _: gfx.ShaderHandle) !void {}
pub fn destroyProgram(_: gfx.ProgramHandle) void {}
pub fn createVertexBuffer(_: gfx.VertexBufferHandle, _: [*]const u8, _: u32, _: shared.VertexLayout) !void {}
pub fn destroyVertexBuffer(_: gfx.VertexBufferHandle) void {}
pub fn beginFrame() !bool {
    return true;
}
pub fn endFrame() !void {}
pub fn setViewport(_: gfx.Rect) void {}
pub fn setScissor(_: gfx.Rect) void {}
pub fn bindProgram(_: gfx.ProgramHandle) void {}
pub fn bindVertexBuffer(_: gfx.VertexBufferHandle) void {}
pub fn draw(_: u32, _: u32, _: u32, _: u32) void {}
