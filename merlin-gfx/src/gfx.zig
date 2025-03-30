const std = @import("std");

const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const types = utils.gfx_types;

const noop = @import("noop/noop.zig");
const vulkan = @import("vulkan/vulkan.zig");

// *********************************************************************************************
// Constants
// *********************************************************************************************

pub const log = std.log.scoped(.gfx);

pub const ShaderHandle = enum(u16) { _ };
pub const ProgramHandle = enum(u16) { _ };
pub const VertexBufferHandle = enum(u16) { _ };
pub const IndexBufferHandle = enum(u16) { _ };
pub const UniformBufferHandle = enum(u16) { _ };
pub const UniformHandle = enum(u16) { _ };
pub const TextureHandle = enum(u16) { _ };
pub const CommandBufferHandle = enum(u16) { _ };
pub const PipelineLayoutHandle = enum(u16) { _ };

pub const MaxShaderHandles = 512;
pub const MaxProgramHandles = 512;
pub const MaxVertexBufferHandles = 512;
pub const MaxIndexBufferHandles = 512;
pub const MaxUniformBufferHandles = 512;
pub const MaxUniformHandles = 512;
pub const MaxTextureHandles = 512;
pub const MaxCommandBufferHandles = 512;
pub const MaxPipelineLayoutHandles = 512;

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

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    swapchainSize: *const fn () [2]u32,
    maxFramesInFlight: *const fn () u32,
    currentFrameInFlight: *const fn () u32,
    createShader: *const fn (loader: utils.loaders.ShaderLoader) anyerror!ShaderHandle,
    destroyShader: *const fn (handle: ShaderHandle) void,
    createProgram: *const fn (vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) anyerror!ProgramHandle,
    destroyProgram: *const fn (handle: ProgramHandle) void,
    createVertexBuffer: *const fn (loader: utils.loaders.VertexBufferLoader) anyerror!VertexBufferHandle,
    destroyVertexBuffer: *const fn (handle: VertexBufferHandle) void,
    createIndexBuffer: *const fn (loader: utils.loaders.IndexBufferLoader) anyerror!IndexBufferHandle,
    destroyIndexBuffer: *const fn (handle: IndexBufferHandle) void,
    createUniformBuffer: *const fn (size: u32) anyerror!UniformBufferHandle,
    destroyUniformBuffer: *const fn (handle: UniformBufferHandle) void,
    updateUniformBuffer: *const fn (handle: UniformBufferHandle, data: []const u8, offset: u32) void,
    createTexture: *const fn (loader: utils.loaders.TextureLoader) anyerror!TextureHandle,
    destroyTexture: *const fn (handle: TextureHandle) void,
    registerUniformName: *const fn (name: []const u8) anyerror!UniformHandle,
    beginFrame: *const fn () anyerror!bool,
    endFrame: *const fn () anyerror!void,
    setViewport: *const fn (position: [2]u32, size: [2]u32) void,
    setScissor: *const fn (position: [2]u32, size: [2]u32) void,
    bindProgram: *const fn (program: ProgramHandle) void,
    bindVertexBuffer: *const fn (vertex_buffer: VertexBufferHandle) void,
    bindIndexBuffer: *const fn (index_buffer: IndexBufferHandle) void,
    bindUniformBuffer: *const fn (uniform: UniformHandle, uniform_buffer: UniformBufferHandle, offset: u32) void,
    bindCombinedSampler: *const fn (uniform: UniformHandle, texture: TextureHandle) void,
    draw: *const fn (vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void,
    drawIndexed: *const fn (index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var current_renderer: RendererType = undefined;

//var mvp_uniform_handle: UniformHandle = undefined;

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
                .swapchainSize = noop.swapchainSize,
                .maxFramesInFlight = noop.maxFramesInFlight,
                .currentFrameInFlight = noop.currentFrameInFlight,
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
                .createTexture = noop.createTexture,
                .destroyTexture = noop.destroyTexture,
                .registerUniformName = noop.registerUniformName,
                .beginFrame = noop.beginFrame,
                .endFrame = noop.endFrame,
                .setViewport = noop.setViewport,
                .setScissor = noop.setScissor,
                .bindProgram = noop.bindProgram,
                .bindVertexBuffer = noop.bindVertexBuffer,
                .bindIndexBuffer = noop.bindIndexBuffer,
                .bindUniformBuffer = noop.bindUniformBuffer,
                .bindCombinedSampler = noop.bindCombinedSampler,
                .draw = noop.draw,
                .drawIndexed = noop.drawIndexed,
            };
        },
        RendererType.vulkan => {
            return VTab{
                .init = vulkan.init,
                .deinit = vulkan.deinit,
                .swapchainSize = vulkan.swapchainSize,
                .maxFramesInFlight = vulkan.maxFramesInFlight,
                .currentFrameInFlight = vulkan.currentFrameInFlight,
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
                .createTexture = vulkan.createTexture,
                .destroyTexture = vulkan.destroyTexture,
                .registerUniformName = vulkan.registerUniformName,
                .beginFrame = vulkan.beginFrame,
                .endFrame = vulkan.endFrame,
                .setViewport = vulkan.setViewport,
                .setScissor = vulkan.setScissor,
                .bindProgram = vulkan.bindProgram,
                .bindVertexBuffer = vulkan.bindVertexBuffer,
                .bindIndexBuffer = vulkan.bindIndexBuffer,
                .bindUniformBuffer = vulkan.bindUniformBuffer,
                .bindCombinedSampler = vulkan.bindCombinedSampler,
                .draw = vulkan.draw,
                .drawIndexed = vulkan.drawIndexed,
            };
        },
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

/// Initializes the renderer.
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

    //mvp_uniform_handle = try createUniformBuffer("u_mvp", @sizeOf(ModelViewProj));
}

/// Deinitializes the renderer.
pub fn deinit() void {
    log.debug("Deinitializing renderer", .{});

    //destroyUniformBuffer(mvp_uniform_handle);

    v_tab.deinit();
    arena_impl.deinit();
}

/// Returns the size of the swapchain.
pub inline fn swapchainSize() [2]u32 {
    return v_tab.swapchainSize();
}

/// Returns the maximum number of frames in flight.
pub inline fn maxFramesInFlight() u32 {
    return v_tab.maxFramesInFlight();
}

/// Returns the current frame in flight.
pub inline fn currentFrameInFlight() u32 {
    return v_tab.currentFrameInFlight();
}

/// Creates a shader from a loader.
pub fn createShader(loader: utils.loaders.ShaderLoader) !ShaderHandle {
    return try v_tab.createShader(loader);
}

/// Destroys a shader.
pub inline fn destroyShader(handle: ShaderHandle) void {
    v_tab.destroyShader(handle);
}

/// Creates a program from vertex and fragment shaders.
pub inline fn createProgram(
    vertex_shader: ShaderHandle,
    fragment_shader: ShaderHandle,
) !ProgramHandle {
    return try v_tab.createProgram(
        vertex_shader,
        fragment_shader,
    );
}

/// Destroys a program.
pub inline fn destroyProgram(handle: ProgramHandle) void {
    v_tab.destroyProgram(handle);
}

/// Creates a vertex buffer from a loader.
pub inline fn createVertexBuffer(loader: utils.loaders.VertexBufferLoader) !VertexBufferHandle {
    return try v_tab.createVertexBuffer(loader);
}

/// Destroys a vertex buffer.
pub inline fn destroyVertexBuffer(handle: VertexBufferHandle) void {
    v_tab.destroyVertexBuffer(handle);
}

/// Creates an index buffer from a loader.
pub inline fn createIndexBuffer(loader: utils.loaders.IndexBufferLoader) !IndexBufferHandle {
    return try v_tab.createIndexBuffer(loader);
}

/// Destroys an index buffer.
pub inline fn destroyIndexBuffer(handle: IndexBufferHandle) void {
    v_tab.destroyIndexBuffer(handle);
}

/// Creates a uniform buffer.
pub inline fn createUniformBuffer(size: u32) !UniformBufferHandle {
    return try v_tab.createUniformBuffer(size);
}

/// Destroys a uniform buffer.
pub inline fn destroyUniformBuffer(handle: UniformBufferHandle) void {
    v_tab.destroyUniformBuffer(handle);
}

/// Updates a uniform buffer.
pub inline fn updateUniformBuffer(handle: UniformBufferHandle, data: []const u8, offset: u32) void {
    v_tab.updateUniformBuffer(handle, data, offset);
}

/// Creates a texture from a loader.
pub inline fn createTexture(loader: utils.loaders.TextureLoader) !TextureHandle {
    return try v_tab.createTexture(loader);
}

/// Destroys a texture.
pub inline fn destroyTexture(handle: TextureHandle) void {
    v_tab.destroyTexture(handle);
}

/// Registers a uniform name.
pub inline fn registerUniformName(name: []const u8) !UniformHandle {
    return try v_tab.registerUniformName(name);
}

/// Begins a frame.
pub inline fn beginFrame() !bool {
    return v_tab.beginFrame();
}

/// Ends a frame.
pub inline fn endFrame() !void {
    defer _ = arena_impl.reset(.retain_capacity);
    return v_tab.endFrame();
}

/// Sets the viewport.
pub inline fn setViewport(position: [2]u32, size: [2]u32) void {
    v_tab.setViewport(position, size);
}

/// Sets the scissor.
pub inline fn setScissor(position: [2]u32, size: [2]u32) void {
    v_tab.setScissor(position, size);
}

pub inline fn bindProgram(handle: ProgramHandle) void {
    v_tab.bindProgram(handle);
}

pub inline fn bindVertexBuffer(handle: VertexBufferHandle) void {
    v_tab.bindVertexBuffer(handle);
}

pub inline fn bindIndexBuffer(handle: IndexBufferHandle) void {
    v_tab.bindIndexBuffer(handle);
}

pub inline fn bindUniformBuffer(
    uniform: UniformHandle,
    uniform_buffer: UniformBufferHandle,
    offset: u32,
) void {
    v_tab.bindUniformBuffer(
        uniform,
        uniform_buffer,
        offset,
    );
}

pub inline fn bindCombinedSampler(uniform: UniformHandle, texture: TextureHandle) void {
    v_tab.bindCombinedSampler(uniform, texture);
}

pub inline fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
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
    v_tab.drawIndexed(
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
