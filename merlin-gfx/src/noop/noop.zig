const std = @import("std");

const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const types = utils.gfx_types;

const gfx = @import("../gfx.zig");

pub fn init(_: std.mem.Allocator, _: *const gfx.Options) !void {}
pub fn deinit() void {}
pub fn getSwapchainSize(_: gfx.FramebufferHandle) [2]u32 {
    return .{ 0, 0 };
}
pub fn getUniformAlignment() u32 {
    return 0;
}
pub fn getMaxFramesInFlight() u32 {
    return 0;
}
pub fn getCurrentFrameInFlight() u32 {
    return 0;
}
pub fn createFramebuffer(_: platform.WindowHandle, _: gfx.RenderPassHandle) !gfx.FramebufferHandle {
    return .{ .handle = undefined };
}
pub fn destroyFramebuffer(_: gfx.FramebufferHandle) void {}
pub fn createRenderPass() !gfx.RenderPassHandle {
    return .{ .handle = undefined };
}
pub fn destroyRenderPass(_: gfx.RenderPassHandle) void {}
pub fn createShader(_: std.io.AnyReader, _: gfx.ShaderOptions) !gfx.ShaderHandle {
    return .{ .handle = undefined };
}
pub fn destroyShader(_: gfx.ShaderHandle) void {}
pub fn createPipelineLayout(_: types.VertexLayout) !gfx.PipelineLayoutHandle {
    return .{ .handle = undefined };
}

pub fn destroyPipelineLayout(_: gfx.PipelineLayoutHandle) void {}
pub fn createProgram(_: gfx.ShaderHandle, _: gfx.ShaderHandle, _: gfx.ProgramOptions) !gfx.ProgramHandle {
    return .{ .handle = undefined };
}
pub fn destroyProgram(_: gfx.ProgramHandle) void {}
pub fn createBuffer(_: u32, _: gfx.BufferUsage, _: gfx.BufferLocation, _: gfx.BufferOptions) !gfx.BufferHandle {
    return .{ .handle = undefined };
}
pub fn destroyBuffer(_: gfx.BufferHandle) void {}
pub fn updateBuffer(_: gfx.BufferHandle, _: std.io.AnyReader, _: u32, _: u32) !void {}
pub fn createTexture(_: std.io.AnyReader, _: u32, _: gfx.TextureOptions) !gfx.TextureHandle {
    return .{ .handle = undefined };
}
pub fn createTextureFromKTX(_: std.io.AnyReader, _: u32, _: gfx.TextureKTXOptions) !gfx.TextureHandle {
    return .{ .handle = undefined };
}
pub fn destroyTexture(_: gfx.TextureHandle) void {}
pub fn beginFrame() !bool {
    return true;
}
pub fn beginRenderPass(_: gfx.FramebufferHandle, _: gfx.RenderPassHandle) !bool {
    return false;
}
pub fn endRenderPass() void {}
pub fn endFrame() !void {}
pub fn setViewport(_: [2]u32, _: [2]u32) void {}
pub fn setScissor(_: [2]u32, _: [2]u32) void {}
pub fn setDebug(_: gfx.DebugOptions) void {}
pub fn setRender(_: gfx.RenderOptions) void {}
pub fn bindPipelineLayout(_: gfx.PipelineLayoutHandle) void {}
pub fn bindProgram(_: gfx.ProgramHandle) void {}
pub fn bindVertexBuffer(_: gfx.BufferHandle, _: u32) void {}
pub fn bindIndexBuffer(_: gfx.BufferHandle, _: u32) void {}
pub fn bindUniformBuffer(_: gfx.NameHandle, _: gfx.BufferHandle, _: u32) void {}
pub fn bindCombinedSampler(_: gfx.NameHandle, _: gfx.TextureHandle) void {}
pub fn pushConstants(_: types.ShaderType, _: u32, _: []const u8) void {}
pub fn draw(_: u32, _: u32, _: u32, _: u32) void {}
pub fn drawIndexed(_: u32, _: u32, _: u32, _: i32, _: u32, _: types.IndexType) void {}
pub fn beginDebugLabel(_: []const u8, _: [4]f32) void {}
pub fn endDebugLabel() void {}
pub fn insertDebugLabel(_: []const u8, _: [4]f32) void {}
