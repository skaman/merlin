const std = @import("std");

const gfx = @import("../gfx.zig");

pub fn init(_: std.mem.Allocator, _: *const gfx.Options) !void {}
pub fn deinit() void {}
pub fn getSwapchainSize() [2]u32 {
    return .{ 0, 0 };
}
pub fn setFramebufferSize(_: [2]u32) void {}
pub fn createShader(_: *const gfx.ShaderData) !gfx.ShaderHandle {
    return 0;
}
pub fn destroyShader(_: gfx.ShaderHandle) void {}
pub fn createProgram(_: gfx.ShaderHandle, _: gfx.ShaderHandle) !gfx.ProgramHandle {
    return 0;
}
pub fn destroyProgram(_: gfx.ProgramHandle) void {}
pub fn createVertexBuffer(_: []const u8, _: gfx.VertexLayout) !gfx.VertexBufferHandle {
    return 0;
}
pub fn destroyVertexBuffer(_: gfx.VertexBufferHandle) void {}
pub fn createIndexBuffer(_: []const u8, _: gfx.IndexType) !gfx.IndexBufferHandle {
    return 0;
}
pub fn destroyIndexBuffer(_: gfx.IndexBufferHandle) void {}
pub fn createUniformBuffer(_: []const u8, _: u32) !gfx.UniformHandle {
    return 0;
}
pub fn destroyUniformBuffer(_: gfx.UniformHandle) void {}
pub fn updateUniformBuffer(_: gfx.UniformHandle, _: []const u8) !void {}
pub fn createCombinedSampler(_: []const u8) !gfx.UniformHandle {
    return 0;
}
pub fn destroyCombinedSampler(_: gfx.UniformHandle) void {}
pub fn createTexture(_: std.io.AnyReader) !gfx.TextureHandle {
    return 0;
}
pub fn destroyTexture(_: gfx.TextureHandle) void {}
pub fn beginFrame() !bool {
    return true;
}
pub fn endFrame() !void {}
pub fn setViewport(_: [2]u32, _: [2]u32) void {}
pub fn setScissor(_: [2]u32, _: [2]u32) void {}
pub fn bindProgram(_: gfx.ProgramHandle) void {}
pub fn bindVertexBuffer(_: gfx.VertexBufferHandle) void {}
pub fn bindIndexBuffer(_: gfx.IndexBufferHandle) void {}
pub fn bindTexture(_: gfx.TextureHandle, _: gfx.UniformHandle) void {}
pub fn draw(_: u32, _: u32, _: u32, _: u32) void {}
pub fn drawIndexed(_: u32, _: u32, _: u32, _: i32, _: u32) void {}
