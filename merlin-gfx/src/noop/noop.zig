const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const gfx = @import("../gfx.zig");

pub fn init(_: std.mem.Allocator, _: *const gfx.Options) !void {}
pub fn deinit() void {}
pub fn swapchainSize() [2]u32 {
    return .{ 0, 0 };
}
pub fn maxFramesInFlight() u32 {
    return 0;
}
pub fn currentFrameInFlight() u32 {
    return 0;
}
pub fn createShader(_: utils.loaders.ShaderLoader) !gfx.ShaderHandle {
    return @enumFromInt(0);
}
pub fn destroyShader(_: gfx.ShaderHandle) void {}
pub fn createProgram(_: gfx.ShaderHandle, _: gfx.ShaderHandle) !gfx.ProgramHandle {
    return @enumFromInt(0);
}
pub fn destroyProgram(_: gfx.ProgramHandle) void {}
pub fn createVertexBuffer(_: utils.loaders.VertexBufferLoader) !gfx.VertexBufferHandle {
    return @enumFromInt(0);
}
pub fn destroyVertexBuffer(_: gfx.VertexBufferHandle) void {}
pub fn createIndexBuffer(_: utils.loaders.IndexBufferLoader) !gfx.IndexBufferHandle {
    return @enumFromInt(0);
}
pub fn destroyIndexBuffer(_: gfx.IndexBufferHandle) void {}
pub fn createUniformBuffer(_: u32) !gfx.UniformBufferHandle {
    return @enumFromInt(0);
}
pub fn destroyUniformBuffer(_: gfx.UniformBufferHandle) void {}
pub fn updateUniformBuffer(_: gfx.UniformBufferHandle, _: []const u8, _: u32) void {}
pub fn createTexture(_: utils.loaders.TextureLoader) !gfx.TextureHandle {
    return @enumFromInt(0);
}
pub fn destroyTexture(_: gfx.TextureHandle) void {}
pub fn registerUniformName(_: []const u8) !gfx.UniformHandle {
    return @enumFromInt(0);
}
pub fn beginFrame() !bool {
    return true;
}
pub fn endFrame() !void {}
pub fn setViewport(_: [2]u32, _: [2]u32) void {}
pub fn setScissor(_: [2]u32, _: [2]u32) void {}
pub fn bindProgram(_: gfx.ProgramHandle) void {}
pub fn bindVertexBuffer(_: gfx.VertexBufferHandle) void {}
pub fn bindIndexBuffer(_: gfx.IndexBufferHandle) void {}
pub fn bindUniformBuffer(_: gfx.UniformHandle, _: gfx.UniformBufferHandle, _: u32) void {}
pub fn bindCombinedSampler(_: gfx.UniformHandle, _: gfx.TextureHandle) void {}
pub fn draw(_: u32, _: u32, _: u32, _: u32) void {}
pub fn drawIndexed(_: u32, _: u32, _: u32, _: i32, _: u32) void {}
