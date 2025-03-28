const std = @import("std");

const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const types = utils.gfx_types;
const zm = @import("zmath");

const noop = @import("noop/noop.zig");
const vulkan = @import("vulkan/vulkan.zig");

pub const log = std.log.scoped(.gfx);

pub const ShaderHandle = u16;
pub const ProgramHandle = u16;
pub const VertexBufferHandle = u16;
pub const IndexBufferHandle = u16;
pub const UniformHandle = u16;
pub const TextureHandle = u16;
pub const CommandBufferHandle = u16;

pub const MaxShaderHandles = 512;
pub const MaxProgramHandles = 512;
pub const MaxVertexBufferHandles = 512;
pub const MaxIndexBufferHandles = 512;
pub const MaxUniformHandles = 512;
pub const MaxTextureHandles = 512;
pub const MaxCommandBufferHandles = 512;

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

pub const Options = struct {
    renderer_type: RendererType,
    enable_vulkan_debug: bool = false,
};

pub const RendererType = enum {
    noop,
    vulkan,
};

pub const ModelViewProj = struct {
    model: zm.Mat align(16),
    view: zm.Mat align(16),
    proj: zm.Mat align(16),
};

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    getSwapchainSize: *const fn () [2]u32,
    createShader: *const fn (loader: utils.loaders.ShaderLoader) anyerror!ShaderHandle,
    destroyShader: *const fn (handle: ShaderHandle) void,
    createProgram: *const fn (vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) anyerror!ProgramHandle,
    destroyProgram: *const fn (handle: ProgramHandle) void,
    createVertexBuffer: *const fn (loader: utils.loaders.VertexBufferLoader) anyerror!VertexBufferHandle,
    destroyVertexBuffer: *const fn (handle: VertexBufferHandle) void,
    createIndexBuffer: *const fn (loader: utils.loaders.IndexBufferLoader) anyerror!IndexBufferHandle,
    destroyIndexBuffer: *const fn (handle: IndexBufferHandle) void,
    createUniformBuffer: *const fn (name: []const u8, size: u32) anyerror!UniformHandle,
    destroyUniformBuffer: *const fn (handle: UniformHandle) void,
    updateUniformBuffer: *const fn (handle: UniformHandle, data: []const u8) anyerror!void,
    createCombinedSampler: *const fn (name: []const u8) anyerror!UniformHandle,
    destroyCombinedSampler: *const fn (handle: UniformHandle) void,
    createTexture: *const fn (loader: utils.loaders.TextureLoader) anyerror!TextureHandle,
    destroyTexture: *const fn (handle: TextureHandle) void,
    beginFrame: *const fn () anyerror!bool,
    endFrame: *const fn () anyerror!void,
    setViewport: *const fn (position: [2]u32, size: [2]u32) void,
    setScissor: *const fn (position: [2]u32, size: [2]u32) void,
    bindProgram: *const fn (program: ProgramHandle) void,
    bindVertexBuffer: *const fn (vertex_buffer: VertexBufferHandle) void,
    bindIndexBuffer: *const fn (index_buffer: IndexBufferHandle) void,
    bindTexture: *const fn (texture: TextureHandle, uniform: UniformHandle) void,
    draw: *const fn (vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void,
    drawIndexed: *const fn (index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var initialized: bool = false;
var current_renderer: RendererType = undefined;

var mvp_uniform_handle: UniformHandle = undefined;

var v_tab: VTab = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn getVTab(renderer_type: RendererType) !VTab {
    switch (renderer_type) {
        RendererType.noop => {
            return VTab{
                .init = noop.init,
                .deinit = noop.deinit,
                .getSwapchainSize = noop.getSwapchainSize,
                .createShader = noop.createShader,
                .destroyShader = noop.destroyShader,
                .createProgram = noop.createProgram,
                .destroyProgram = noop.destroyProgram,
                .createVertexBuffer = noop.createVertexBuffer,
                .destroyVertexBuffer = noop.destroyVertexBuffer,
                .createIndexBuffer = noop.createIndexBuffer,
                .destroyIndexBuffer = noop.destroyIndexBuffer,
                .createUniformBuffer = noop.createUniformBuffer,
                .destroyUniformBuffer = noop.destroyUniformBuffer,
                .updateUniformBuffer = noop.updateUniformBuffer,
                .createCombinedSampler = noop.createCombinedSampler,
                .destroyCombinedSampler = noop.destroyCombinedSampler,
                .createTexture = noop.createTexture,
                .destroyTexture = noop.destroyTexture,
                .beginFrame = noop.beginFrame,
                .endFrame = noop.endFrame,
                .setViewport = noop.setViewport,
                .setScissor = noop.setScissor,
                .bindProgram = noop.bindProgram,
                .bindVertexBuffer = noop.bindVertexBuffer,
                .bindIndexBuffer = noop.bindIndexBuffer,
                .bindTexture = noop.bindTexture,
                .draw = noop.draw,
                .drawIndexed = noop.drawIndexed,
            };
        },
        RendererType.vulkan => {
            return VTab{
                .init = vulkan.init,
                .deinit = vulkan.deinit,
                .getSwapchainSize = vulkan.getSwapchainSize,
                .createShader = vulkan.createShader,
                .destroyShader = vulkan.destroyShader,
                .createProgram = vulkan.createProgram,
                .destroyProgram = vulkan.destroyProgram,
                .createVertexBuffer = vulkan.createVertexBuffer,
                .destroyVertexBuffer = vulkan.destroyVertexBuffer,
                .createIndexBuffer = vulkan.createIndexBuffer,
                .destroyIndexBuffer = vulkan.destroyIndexBuffer,
                .createUniformBuffer = vulkan.createUniformBuffer,
                .destroyUniformBuffer = vulkan.destroyUniformBuffer,
                .updateUniformBuffer = vulkan.updateUniformBuffer,
                .createCombinedSampler = vulkan.createCombinedSampler,
                .destroyCombinedSampler = vulkan.destroyCombinedSampler,
                .createTexture = vulkan.createTexture,
                .destroyTexture = vulkan.destroyTexture,
                .beginFrame = vulkan.beginFrame,
                .endFrame = vulkan.endFrame,
                .setViewport = vulkan.setViewport,
                .setScissor = vulkan.setScissor,
                .bindProgram = vulkan.bindProgram,
                .bindVertexBuffer = vulkan.bindVertexBuffer,
                .bindIndexBuffer = vulkan.bindIndexBuffer,
                .bindTexture = vulkan.bindTexture,
                .draw = vulkan.draw,
                .drawIndexed = vulkan.drawIndexed,
            };
        },
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(
    allocator: std.mem.Allocator,
    options: Options,
) !void {
    log.debug("Initializing renderer", .{});

    gpa = allocator;

    arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena_impl.deinit();
    arena = arena_impl.allocator();

    v_tab = try getVTab(options.renderer_type);

    try v_tab.init(gpa, &options);
    errdefer v_tab.deinit();

    current_renderer = options.renderer_type;

    initialized = true;

    mvp_uniform_handle = try createUniformBuffer("u_mvp", @sizeOf(ModelViewProj));
}

pub fn deinit() void {
    std.debug.assert(initialized);

    log.debug("Deinitializing renderer", .{});

    destroyUniformBuffer(mvp_uniform_handle);

    v_tab.deinit();
    arena_impl.deinit();

    initialized = false;
}

pub inline fn getSwapchainSize() [2]u32 {
    std.debug.assert(initialized);
    return v_tab.getSwapchainSize();
}

pub inline fn setModelViewProj(mvp: ModelViewProj) void {
    std.debug.assert(initialized);

    const ptr: [*]const u8 = @ptrCast(&mvp);
    updateUniformBuffer(
        mvp_uniform_handle,
        ptr[0..@sizeOf(ModelViewProj)],
    );
}

pub fn createShader(loader: utils.loaders.ShaderLoader) !ShaderHandle {
    std.debug.assert(initialized);

    return try v_tab.createShader(loader);
}

pub inline fn destroyShader(handle: ShaderHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyShader(handle);
}

pub inline fn createProgram(vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) !ProgramHandle {
    std.debug.assert(initialized);
    return try v_tab.createProgram(vertex_shader, fragment_shader);
}

pub inline fn destroyProgram(handle: ProgramHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyProgram(handle);
}

pub inline fn createVertexBuffer(loader: utils.loaders.VertexBufferLoader) !VertexBufferHandle {
    std.debug.assert(initialized);
    return try v_tab.createVertexBuffer(loader);
}

pub inline fn destroyVertexBuffer(handle: VertexBufferHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyVertexBuffer(handle);
}

pub inline fn createIndexBuffer(loader: utils.loaders.IndexBufferLoader) !IndexBufferHandle {
    std.debug.assert(initialized);
    return try v_tab.createIndexBuffer(loader);
}

pub inline fn destroyIndexBuffer(handle: IndexBufferHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyIndexBuffer(handle);
}

pub inline fn createUniformBuffer(name: []const u8, size: u32) !UniformHandle {
    std.debug.assert(initialized);
    return try v_tab.createUniformBuffer(name, size);
}

pub inline fn destroyUniformBuffer(handle: UniformHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyUniformBuffer(handle);
}

pub inline fn updateUniformBuffer(handle: UniformHandle, data: []const u8) void {
    std.debug.assert(initialized);
    v_tab.updateUniformBuffer(handle, data) catch |err| {
        log.err("Failed to update uniform buffer: {}", .{err});
    };
}

pub inline fn createCombinedSampler(name: []const u8) !UniformHandle {
    std.debug.assert(initialized);
    return try v_tab.createCombinedSampler(name);
}

pub inline fn destroyCombinedSampler(handle: UniformHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyCombinedSampler(handle);
}

pub inline fn createTexture(loader: utils.loaders.TextureLoader) !TextureHandle {
    std.debug.assert(initialized);
    return try v_tab.createTexture(loader);
}

pub inline fn destroyTexture(handle: TextureHandle) void {
    std.debug.assert(initialized);
    v_tab.destroyTexture(handle);
}

pub inline fn beginFrame() !bool {
    std.debug.assert(initialized);
    return v_tab.beginFrame();
}

pub inline fn endFrame() !void {
    std.debug.assert(initialized);

    const result = v_tab.endFrame();
    _ = arena_impl.reset(.retain_capacity);
    return result;
}

pub inline fn setViewport(position: [2]u32, size: [2]u32) void {
    std.debug.assert(initialized);
    v_tab.setViewport(position, size);
}

pub inline fn setScissor(position: [2]u32, size: [2]u32) void {
    std.debug.assert(initialized);
    v_tab.setScissor(position, size);
}

pub inline fn bindProgram(handle: ProgramHandle) void {
    std.debug.assert(initialized);
    v_tab.bindProgram(handle);
}

pub inline fn bindVertexBuffer(handle: VertexBufferHandle) void {
    std.debug.assert(initialized);
    v_tab.bindVertexBuffer(handle);
}

pub inline fn bindIndexBuffer(handle: IndexBufferHandle) void {
    std.debug.assert(initialized);
    v_tab.bindIndexBuffer(handle);
}

pub inline fn bindTexture(texture: TextureHandle, uniform: UniformHandle) void {
    std.debug.assert(initialized);
    v_tab.bindTexture(texture, uniform);
}

pub inline fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    std.debug.assert(initialized);
    v_tab.draw(
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub inline fn drawIndexed(
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    std.debug.assert(initialized);
    v_tab.drawIndexed(
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
