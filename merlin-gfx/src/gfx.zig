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
pub const BufferHandle = enum(u16) { _ };
pub const UniformHandle = enum(u16) { _ };
pub const TextureHandle = enum(u16) { _ };
pub const CommandBufferHandle = enum(u16) { _ };
pub const PipelineLayoutHandle = enum(u16) { _ };

pub const MaxShaderHandles = 512;
pub const MaxProgramHandles = 512;
pub const MaxBufferHandles = 512;
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

pub const BufferUsage = packed struct(u8) {
    index: bool = false,
    vertex: bool = false,
    uniform: bool = false,

    _padding: u5 = 0,
};

pub const BufferLocation = enum(u8) {
    host,
    device,

    pub fn name(self: BufferLocation) []const u8 {
        return switch (self) {
            .host => "host",
            .device => "device",
        };
    }
};

pub const ImageFormat = enum(u8) {
    rgba8,
    rgba8_srgb,
    rg8,
    r8,
    rgba16f,

    pub fn name(self: ImageFormat) []const u8 {
        return switch (self) {
            .rgba8 => "rgba8",
            .rgba8_srgb => "rgba8_srgb",
            .rg8 => "rg8",
            .r8 => "r8",
            .rgba16f => "rgba16f",
        };
    }
};

pub const TextureTiling = enum(u8) {
    linear,
    optimal,

    pub fn name(self: TextureTiling) []const u8 {
        return switch (self) {
            .linear => "linear",
            .optimal => "optimal",
        };
    }
};

pub const ShaderOptions = struct {
    debug_name: ?[]const u8 = null,
};

pub const TextureOptions = struct {
    format: ImageFormat,
    width: u32,
    height: u32,
    depth: u32 = 1,
    array_layers: u32 = 1,
    tiling: TextureTiling = .optimal,
    is_cubemap: bool = false,
    is_array: bool = false,
    generate_mipmaps: bool = false,
    debug_name: ?[]const u8 = null,
};

pub const TextureKTXOptions = struct {
    debug_name: ?[]const u8 = null,
};

pub const BufferOptions = struct {
    debug_name: ?[]const u8 = null,
};

pub fn UniformArray(comptime THandle: type) type {
    return struct {
        const Self = @This();
        handle: BufferHandle,

        pub fn init(
            size: u32,
            usage: BufferUsage,
            location: BufferLocation,
            options: BufferOptions,
        ) !Self {
            return .{
                .handle = try createBuffer(
                    stride() * size,
                    usage,
                    location,
                    options,
                ),
            };
        }

        pub fn deinit(self: *Self) void {
            destroyBuffer(self.handle);
        }

        pub fn update(
            self: *Self,
            index: u32,
            reader: std.io.AnyReader,
        ) !void {
            try updateBuffer(
                self.handle,
                reader,
                offset(index),
                @sizeOf(THandle),
            );
        }

        pub fn updateFromMemory(
            self: *Self,
            index: u32,
            data: []const u8,
        ) !void {
            try updateBufferFromMemory(
                self.handle,
                data,
                self.offset(index),
            );
        }

        pub fn offset(_: *Self, index: u32) u32 {
            return index * stride();
        }

        fn stride() u32 {
            const alignment = uniformAlignment();
            return ((@sizeOf(THandle) + alignment - 1) / alignment) * alignment;
        }
    };
}

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    swapchainSize: *const fn () [2]u32,
    uniformAlignment: *const fn () u32,
    maxFramesInFlight: *const fn () u32,
    currentFrameInFlight: *const fn () u32,
    createShader: *const fn (reader: std.io.AnyReader, options: ShaderOptions) anyerror!ShaderHandle,
    destroyShader: *const fn (handle: ShaderHandle) void,
    createPipelineLayout: *const fn (vertex_layout: types.VertexLayout) anyerror!PipelineLayoutHandle,
    destroyPipelineLayout: *const fn (handle: PipelineLayoutHandle) void,
    createProgram: *const fn (vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) anyerror!ProgramHandle,
    destroyProgram: *const fn (handle: ProgramHandle) void,
    createBuffer: *const fn (size: u32, usage: BufferUsage, location: BufferLocation, options: BufferOptions) anyerror!BufferHandle,
    destroyBuffer: *const fn (handle: BufferHandle) void,
    updateBuffer: *const fn (handle: BufferHandle, reader: std.io.AnyReader, offset: u32, size: u32) anyerror!void,
    createTexture: *const fn (reader: std.io.AnyReader, size: u32, options: TextureOptions) anyerror!TextureHandle,
    createTextureFromKTX: *const fn (reader: std.io.AnyReader, size: u32, options: TextureKTXOptions) anyerror!TextureHandle,
    destroyTexture: *const fn (handle: TextureHandle) void,
    registerUniformName: *const fn (name: []const u8) anyerror!UniformHandle,
    beginFrame: *const fn () anyerror!bool,
    endFrame: *const fn () anyerror!void,
    setViewport: *const fn (position: [2]u32, size: [2]u32) void,
    setScissor: *const fn (position: [2]u32, size: [2]u32) void,
    bindPipelineLayout: *const fn (handle: PipelineLayoutHandle) void,
    bindProgram: *const fn (program: ProgramHandle) void,
    bindVertexBuffer: *const fn (buffer: BufferHandle, offset: u32) void,
    bindIndexBuffer: *const fn (buffer: BufferHandle, offset: u32) void,
    bindUniformBuffer: *const fn (uniform: UniformHandle, buffer: BufferHandle, offset: u32) void,
    bindCombinedSampler: *const fn (uniform: UniformHandle, texture: TextureHandle) void,
    draw: *const fn (vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void,
    drawIndexed: *const fn (index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32, index_type: types.IndexType) void,
    beginDebugLabel: *const fn (label_name: []const u8, color: [4]f32) void,
    endDebugLabel: *const fn () void,
    insertDebugLabel: *const fn (label_name: []const u8, color: [4]f32) void,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var current_renderer: RendererType = undefined;

var v_tab: VTab = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn getVTab(renderer_type: RendererType) !VTab {
    switch (renderer_type) {
        RendererType.noop => {
            return .{
                .init = noop.init,
                .deinit = noop.deinit,
                .swapchainSize = noop.swapchainSize,
                .uniformAlignment = noop.uniformAlignment,
                .maxFramesInFlight = noop.maxFramesInFlight,
                .currentFrameInFlight = noop.currentFrameInFlight,
                .createShader = noop.createShader,
                .destroyShader = noop.destroyShader,
                .createPipelineLayout = noop.createPipelineLayout,
                .destroyPipelineLayout = noop.destroyPipelineLayout,
                .createProgram = noop.createProgram,
                .destroyProgram = noop.destroyProgram,
                .createBuffer = noop.createBuffer,
                .destroyBuffer = noop.destroyBuffer,
                .updateBuffer = noop.updateBuffer,
                .createTexture = noop.createTexture,
                .createTextureFromKTX = noop.createTextureFromKTX,
                .destroyTexture = noop.destroyTexture,
                .registerUniformName = noop.registerUniformName,
                .beginFrame = noop.beginFrame,
                .endFrame = noop.endFrame,
                .setViewport = noop.setViewport,
                .setScissor = noop.setScissor,
                .bindPipelineLayout = noop.bindPipelineLayout,
                .bindProgram = noop.bindProgram,
                .bindVertexBuffer = noop.bindVertexBuffer,
                .bindIndexBuffer = noop.bindIndexBuffer,
                .bindUniformBuffer = noop.bindUniformBuffer,
                .bindCombinedSampler = noop.bindCombinedSampler,
                .draw = noop.draw,
                .drawIndexed = noop.drawIndexed,
                .beginDebugLabel = noop.beginDebugLabel,
                .endDebugLabel = noop.endDebugLabel,
                .insertDebugLabel = noop.insertDebugLabel,
            };
        },
        RendererType.vulkan => {
            return .{
                .init = vulkan.init,
                .deinit = vulkan.deinit,
                .swapchainSize = vulkan.swapchainSize,
                .uniformAlignment = vulkan.uniformAlignment,
                .maxFramesInFlight = vulkan.maxFramesInFlight,
                .currentFrameInFlight = vulkan.currentFrameInFlight,
                .createShader = vulkan.createShader,
                .destroyShader = vulkan.destroyShader,
                .createPipelineLayout = vulkan.createPipelineLayout,
                .destroyPipelineLayout = vulkan.destroyPipelineLayout,
                .createProgram = vulkan.createProgram,
                .destroyProgram = vulkan.destroyProgram,
                .createBuffer = vulkan.createBuffer,
                .destroyBuffer = vulkan.destroyBuffer,
                .updateBuffer = vulkan.updateBuffer,
                .createTexture = vulkan.createTexture,
                .createTextureFromKTX = vulkan.createTextureFromKTX,
                .destroyTexture = vulkan.destroyTexture,
                .registerUniformName = vulkan.registerUniformName,
                .beginFrame = vulkan.beginFrame,
                .endFrame = vulkan.endFrame,
                .setViewport = vulkan.setViewport,
                .setScissor = vulkan.setScissor,
                .bindPipelineLayout = vulkan.bindPipelineLayout,
                .bindProgram = vulkan.bindProgram,
                .bindVertexBuffer = vulkan.bindVertexBuffer,
                .bindIndexBuffer = vulkan.bindIndexBuffer,
                .bindUniformBuffer = vulkan.bindUniformBuffer,
                .bindCombinedSampler = vulkan.bindCombinedSampler,
                .draw = vulkan.draw,
                .drawIndexed = vulkan.drawIndexed,
                .beginDebugLabel = vulkan.beginDebugLabel,
                .endDebugLabel = vulkan.endDebugLabel,
                .insertDebugLabel = vulkan.insertDebugLabel,
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
}

/// Deinitializes the renderer.
pub fn deinit() void {
    log.debug("Deinitializing renderer", .{});

    v_tab.deinit();
    arena_impl.deinit();
}

/// Returns the size of the swapchain.
pub inline fn swapchainSize() [2]u32 {
    return v_tab.swapchainSize();
}

/// Returns the stride of a uniform buffer.
pub inline fn uniformAlignment() u32 {
    return v_tab.uniformAlignment();
}

/// Returns the maximum number of frames in flight.
/// This is the number of frames that can be rendered simultaneously.
pub inline fn maxFramesInFlight() u32 {
    return v_tab.maxFramesInFlight();
}

/// Returns the current frame in flight.
/// This is the index of the current frame being rendered.
/// This value is in the range [0, maxFramesInFlight).
pub inline fn currentFrameInFlight() u32 {
    return v_tab.currentFrameInFlight();
}

/// Creates a shader from a loader.
pub fn createShader(reader: std.io.AnyReader, options: ShaderOptions) !ShaderHandle {
    return try v_tab.createShader(reader, options);
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

/// Creates a pipeline layout.
pub inline fn createPipelineLayout(vertex_layout: types.VertexLayout) !PipelineLayoutHandle {
    return try v_tab.createPipelineLayout(vertex_layout);
}

/// Destroys a pipeline layout.
pub inline fn destroyPipelineLayout(handle: PipelineLayoutHandle) void {
    v_tab.destroyPipelineLayout(handle);
}

/// Creates a buffer.
pub inline fn createBuffer(
    size: u32,
    usage: BufferUsage,
    location: BufferLocation,
    options: BufferOptions,
) !BufferHandle {
    return try v_tab.createBuffer(size, usage, location, options);
}

/// Destroys a buffer.
pub inline fn destroyBuffer(handle: BufferHandle) void {
    v_tab.destroyBuffer(handle);
}

/// Updates a buffer.
pub inline fn updateBuffer(
    handle: BufferHandle,
    reader: std.io.AnyReader,
    offset: u32,
    size: u32,
) !void {
    try v_tab.updateBuffer(handle, reader, offset, size);
}

pub inline fn updateBufferFromMemory(
    handle: BufferHandle,
    data: []const u8,
    offset: u32,
) !void {
    var stream = std.io.fixedBufferStream(data);
    try v_tab.updateBuffer(
        handle,
        stream.reader().any(),
        offset,
        @intCast(data.len),
    );
}

/// Creates a texture from a loader.
pub inline fn createTexture(reader: std.io.AnyReader, size: u32, options: TextureOptions) !TextureHandle {
    return try v_tab.createTexture(reader, size, options);
}

pub inline fn createTextureFromMemory(
    data: []const u8,
    options: TextureOptions,
) !TextureHandle {
    var stream = std.io.fixedBufferStream(data);
    return try v_tab.createTexture(stream.reader().any(), data.len, options);
}

/// Creates a KTX texture from a loader.
pub inline fn createTextureFromKTX(
    reader: std.io.AnyReader,
    size: u32,
    options: TextureKTXOptions,
) !TextureHandle {
    return try v_tab.createTextureFromKTX(reader, size, options);
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

pub fn bindPipelineLayout(handle: PipelineLayoutHandle) void {
    v_tab.bindPipelineLayout(handle);
}

pub inline fn bindProgram(handle: ProgramHandle) void {
    v_tab.bindProgram(handle);
}

pub inline fn bindVertexBuffer(handle: BufferHandle, offset: u32) void {
    v_tab.bindVertexBuffer(handle, offset);
}

pub inline fn bindIndexBuffer(handle: BufferHandle, offset: u32) void {
    v_tab.bindIndexBuffer(handle, offset);
}

pub inline fn bindUniformBuffer(
    uniform: UniformHandle,
    buffer: BufferHandle,
    offset: u32,
) void {
    v_tab.bindUniformBuffer(
        uniform,
        buffer,
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
    index_type: types.IndexType,
) void {
    v_tab.drawIndexed(
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
        index_type,
    );
}

pub inline fn beginDebugLabel(
    label_name: []const u8,
    color: [4]f32,
) void {
    v_tab.beginDebugLabel(label_name, color);
}

pub inline fn endDebugLabel() void {
    v_tab.endDebugLabel();
}

pub inline fn insertDebugLabel(
    label_name: []const u8,
    color: [4]f32,
) void {
    v_tab.insertDebugLabel(label_name, color);
}
