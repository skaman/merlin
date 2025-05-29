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

pub const FramebufferHandle = packed struct { handle: *anyopaque };
pub const ShaderHandle = packed struct { handle: *anyopaque };
pub const ProgramHandle = packed struct { handle: *anyopaque };
pub const BufferHandle = packed struct { handle: *anyopaque };
pub const TextureHandle = packed struct { handle: *anyopaque };
pub const ImageHandle = packed struct { handle: *anyopaque };
pub const ImageViewHandle = packed struct { handle: *anyopaque };
pub const PipelineLayoutHandle = packed struct { handle: *anyopaque };
pub const CommandBufferHandle = packed struct { handle: *anyopaque };
pub const NameHandle = packed struct { handle: u64 };

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

pub const Options = struct {
    renderer_type: RendererType,
    window_handle: platform.WindowHandle,
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
    bgra8,
    bgra8_srgb,
    rg8,
    r8,
    rgba16f,
    d32f,
    d32f_s8,
    d24_s8,

    pub fn name(self: ImageFormat) []const u8 {
        return switch (self) {
            .rgba8 => "rgba8",
            .rgba8_srgb => "rgba8_srgb",
            .bgra8 => "bgra8",
            .bgra8_srgb => "bgra8_srgb",
            .rg8 => "rg8",
            .r8 => "r8",
            .rgba16f => "rgba16f",
            .d32f => "d32f",
            .d32f_s8 => "d32f_s8",
            .d24_s8 => "d24_s8",
        };
    }
};

pub const AttachmentLoadOp = enum(u8) {
    load,
    clear,
    dont_care,

    pub fn name(self: AttachmentLoadOp) []const u8 {
        return switch (self) {
            .load => "load",
            .clear => "clear",
            .dont_care => "dont_care",
        };
    }
};

pub const AttachmentStoreOp = enum(u8) {
    store,
    dont_care,

    pub fn name(self: AttachmentStoreOp) []const u8 {
        return switch (self) {
            .store => "store",
            .dont_care => "dont_care",
        };
    }
};

pub const Attachment = packed struct {
    image: ImageHandle,
    image_view: ImageViewHandle,
    format: ImageFormat,
    load_op: AttachmentLoadOp,
    store_op: AttachmentStoreOp,
};

pub const RenderPassOptions = struct {
    color_attachments: []const Attachment,
    depth_attachment: ?Attachment = null,
};

pub const TextureTiling = enum(u8) { // TODO: rename in ImageTiling
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

pub const ProgramOptions = struct {
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

pub const ImageUsage = packed struct(u8) {
    color_attachment: bool = false,
    depth_stencil_attachment: bool = false,

    _padding: u6 = 0,
};

pub const ImageLocation = enum(u8) {
    host,
    device,

    pub fn name(self: ImageLocation) []const u8 {
        return switch (self) {
            .host => "host",
            .device => "device",
        };
    }
};

pub const ImageAspect = packed struct(u8) {
    color: bool = false,
    depth: bool = false,
    stencil: bool = false,

    _padding: u5 = 0,
};

pub const ImageOptions = struct {
    format: ImageFormat,
    width: u32,
    height: u32,
    depth: u32 = 1,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    tiling: TextureTiling = .optimal,
    usage: ImageUsage = .{},
    location: ImageLocation = .device,
};

pub const ImageViewOptions = struct {
    format: ImageFormat,
    is_cubemap: bool = false,
    is_array: bool = false,
    aspect: ImageAspect = .{},
    level_count: u32 = 1,
    layer_count: u32 = 1,
    debug_name: ?[]const u8 = null,
};

pub const BufferOptions = struct {
    debug_name: ?[]const u8 = null,
};

pub const DebugOptions = packed struct {
    wireframe: bool = false,
};

pub const CullMode = enum(u2) {
    none,
    front,
    back,
    front_and_back,

    pub fn name(self: CullMode) []const u8 {
        return switch (self) {
            .none => "none",
            .front => "front",
            .back => "back",
            .front_and_back => "front_and_back",
        };
    }
};

pub const BlendFactor = enum(u4) {
    zero,
    one,
    src_color,
    one_minus_src_color,
    dst_color,
    one_minus_dst_color,
    src_alpha,
    one_minus_src_alpha,
    dst_alpha,
    one_minus_dst_alpha,

    pub fn name(self: BlendFactor) []const u8 {
        return switch (self) {
            .zero => "zero",
            .one => "one",
            .src_color => "src_color",
            .one_minus_src_color => "one_minus_src_color",
            .dst_color => "dst_color",
            .one_minus_dst_color => "one_minus_dst_color",
            .src_alpha => "src_alpha",
            .one_minus_src_alpha => "one_minus_src_alpha",
            .dst_alpha => "dst_alpha",
            .one_minus_dst_alpha => "one_minus_dst_alpha",
        };
    }
};

pub const BlendOp = enum(u4) {
    add,
    subtract,
    reverse_subtract,
    min,
    max,

    pub fn name(self: BlendOp) []const u8 {
        return switch (self) {
            .add => "add",
            .subtract => "subtract",
            .reverse_subtract => "reverse_subtract",
            .min => "min",
            .max => "max",
        };
    }
};

pub const BlendWriteMask = packed struct {
    r: bool = true,
    g: bool = true,
    b: bool = true,
    a: bool = true,
};

pub const BlendOptions = packed struct {
    enabled: bool = false,
    src_color_factor: BlendFactor = .src_alpha,
    dst_color_factor: BlendFactor = .one_minus_src_alpha,
    color_op: BlendOp = .add,
    src_alpha_factor: BlendFactor = .one,
    dst_alpha_factor: BlendFactor = .one_minus_src_alpha,
    alpha_op: BlendOp = .add,
    write_mask: BlendWriteMask = .{},
};

pub const FrontFace = enum(u1) {
    counter_clockwise,
    clockwise,

    pub fn name(self: FrontFace) []const u8 {
        return switch (self) {
            .counter_clockwise => "counter_clockwise",
            .clockwise => "clockwise",
        };
    }
};

pub const CompareOp = enum(u3) {
    never,
    less,
    equal,
    less_or_equal,
    greater,
    not_equal,
    greater_or_equal,
    always,

    pub fn name(self: CompareOp) []const u8 {
        return switch (self) {
            .never => "never",
            .less => "less",
            .equal => "equal",
            .less_or_equal => "less_or_equal",
            .greater => "greater",
            .not_equal => "not_equal",
            .greater_or_equal => "greater_or_equal",
            .always => "always",
        };
    }
};

pub const DepthOptions = packed struct {
    enabled: bool = false,
    write_enabled: bool = true,
    compare_op: CompareOp = .less,
    depth_bounds_test_enabled: bool = false,
    stencil_test_enabled: bool = false,
};

pub const RenderOptions = packed struct {
    cull_mode: CullMode = .back,
    front_face: FrontFace = .counter_clockwise,
    //msaa: bool = false,
    blend: BlendOptions = .{},
    depth: DepthOptions = .{},
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
            const alignment = getUniformAlignment();
            return ((@sizeOf(THandle) + alignment - 1) / alignment) * alignment;
        }
    };
}

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    getSwapchainSize: *const fn (framebuffer_handle: FramebufferHandle) [2]u32,
    getSurfaceImage: *const fn (framebuffer_handle: FramebufferHandle) ImageHandle,
    getSurfaceImageView: *const fn (framebuffer_handle: FramebufferHandle) ImageViewHandle,
    getSurfaceColorFormat: *const fn () ImageFormat,
    getSurfaceDepthFormat: *const fn () ImageFormat,
    getUniformAlignment: *const fn () u32,
    getMaxFramesInFlight: *const fn () u32,
    getCurrentFrameInFlight: *const fn () u32,
    createFramebuffer: *const fn (window_handle: platform.WindowHandle) anyerror!FramebufferHandle,
    destroyFramebuffer: *const fn (framebuffer_handle: FramebufferHandle) void,
    createImage: *const fn (image_options: ImageOptions) anyerror!ImageHandle,
    destroyImage: *const fn (image_handle: ImageHandle) void,
    createImageView: *const fn (image_handle: ImageHandle, options: ImageViewOptions) anyerror!ImageViewHandle,
    destroyImageView: *const fn (image_view_handle: ImageViewHandle) void,
    createShader: *const fn (reader: std.io.AnyReader, options: ShaderOptions) anyerror!ShaderHandle,
    destroyShader: *const fn (shader_handle: ShaderHandle) void,
    createPipelineLayout: *const fn (vertex_layout: types.VertexLayout) anyerror!PipelineLayoutHandle,
    destroyPipelineLayout: *const fn (pipeline_layout_handle: PipelineLayoutHandle) void,
    createProgram: *const fn (vertex_shader_handle: ShaderHandle, fragment_shader_handle: ShaderHandle, options: ProgramOptions) anyerror!ProgramHandle,
    destroyProgram: *const fn (program_handle: ProgramHandle) void,
    createBuffer: *const fn (size: u32, usage: BufferUsage, location: BufferLocation, options: BufferOptions) anyerror!BufferHandle,
    destroyBuffer: *const fn (buffer_handle: BufferHandle) void,
    updateBuffer: *const fn (buffer_handle: BufferHandle, reader: std.io.AnyReader, offset: u32, size: u32) anyerror!void,
    createTexture: *const fn (reader: std.io.AnyReader, size: u32, options: TextureOptions) anyerror!TextureHandle,
    createTextureFromKTX: *const fn (reader: std.io.AnyReader, size: u32, options: TextureKTXOptions) anyerror!TextureHandle,
    destroyTexture: *const fn (texture_handle: TextureHandle) void,
    beginFrame: *const fn () anyerror!bool,
    endFrame: *const fn () anyerror!void,
    beginRenderPass: *const fn (framebuffer_handle: FramebufferHandle, options: RenderPassOptions) anyerror!bool,
    endRenderPass: *const fn () void,
    setViewport: *const fn (position: [2]u32, size: [2]u32) void,
    setScissor: *const fn (position: [2]u32, size: [2]u32) void,
    setDebug: *const fn (debug_options: DebugOptions) void,
    setRender: *const fn (render_options: RenderOptions) void,
    bindPipelineLayout: *const fn (pipeline_layout_handle: PipelineLayoutHandle) void,
    bindProgram: *const fn (program_handle: ProgramHandle) void,
    bindVertexBuffer: *const fn (buffer_handle: BufferHandle, offset: u32) void,
    bindIndexBuffer: *const fn (buffer_handle: BufferHandle, offset: u32) void,
    bindUniformBuffer: *const fn (name_handle: NameHandle, buffer_handle: BufferHandle, offset: u32) void,
    bindCombinedSampler: *const fn (name_handle: NameHandle, texture_handle: TextureHandle) void,
    pushConstants: *const fn (shader_stage: types.ShaderType, offset: u32, data: []const u8) void,
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
                .getSwapchainSize = noop.getSwapchainSize,
                .getSurfaceImage = noop.getSurfaceImage,
                .getSurfaceImageView = noop.getSurfaceImageView,
                .getSurfaceColorFormat = noop.getSurfaceColorFormat,
                .getSurfaceDepthFormat = noop.getSurfaceDepthFormat,
                .getUniformAlignment = noop.getUniformAlignment,
                .getMaxFramesInFlight = noop.getMaxFramesInFlight,
                .getCurrentFrameInFlight = noop.getCurrentFrameInFlight,
                .createFramebuffer = noop.createFramebuffer,
                .destroyFramebuffer = noop.destroyFramebuffer,
                .createImage = noop.createImage,
                .destroyImage = noop.destroyImage,
                .createImageView = noop.createImageView,
                .destroyImageView = noop.destroyImageView,
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
                .beginFrame = noop.beginFrame,
                .endFrame = noop.endFrame,
                .beginRenderPass = noop.beginRenderPass,
                .endRenderPass = noop.endRenderPass,
                .setViewport = noop.setViewport,
                .setScissor = noop.setScissor,
                .setDebug = noop.setDebug,
                .setRender = noop.setRender,
                .bindPipelineLayout = noop.bindPipelineLayout,
                .bindProgram = noop.bindProgram,
                .bindVertexBuffer = noop.bindVertexBuffer,
                .bindIndexBuffer = noop.bindIndexBuffer,
                .bindUniformBuffer = noop.bindUniformBuffer,
                .bindCombinedSampler = noop.bindCombinedSampler,
                .pushConstants = noop.pushConstants,
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
                .getSwapchainSize = vulkan.getSwapchainSize,
                .getSurfaceImage = vulkan.getSurfaceImage,
                .getSurfaceImageView = vulkan.getSurfaceImageView,
                .getSurfaceColorFormat = vulkan.getSurfaceColorFormat,
                .getSurfaceDepthFormat = vulkan.getSurfaceDepthFormat,
                .getUniformAlignment = vulkan.getUniformAlignment,
                .getMaxFramesInFlight = vulkan.getMaxFramesInFlight,
                .getCurrentFrameInFlight = vulkan.getCurrentFrameInFlight,
                .createFramebuffer = vulkan.createFramebuffer,
                .destroyFramebuffer = vulkan.destroyFramebuffer,
                .createImage = vulkan.createImage,
                .destroyImage = vulkan.destroyImage,
                .createImageView = vulkan.createImageView,
                .destroyImageView = vulkan.destroyImageView,
                // .createRenderPass = vulkan.createRenderPass,
                // .destroyRenderPass = vulkan.destroyRenderPass,
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
                .beginFrame = vulkan.beginFrame,
                .endFrame = vulkan.endFrame,
                .beginRenderPass = vulkan.beginRenderPass,
                .endRenderPass = vulkan.endRenderPass,
                .setViewport = vulkan.setViewport,
                .setScissor = vulkan.setScissor,
                .setDebug = vulkan.setDebug,
                .setRender = vulkan.setRender,
                .bindPipelineLayout = vulkan.bindPipelineLayout,
                .bindProgram = vulkan.bindProgram,
                .bindVertexBuffer = vulkan.bindVertexBuffer,
                .bindIndexBuffer = vulkan.bindIndexBuffer,
                .bindUniformBuffer = vulkan.bindUniformBuffer,
                .bindCombinedSampler = vulkan.bindCombinedSampler,
                .pushConstants = vulkan.pushConstants,
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
pub inline fn getSwapchainSize(framebuffer_handle: FramebufferHandle) [2]u32 {
    return v_tab.getSwapchainSize(framebuffer_handle);
}

/// Returns the surface image of the swapchain.
pub inline fn getSurfaceImage(framebuffer_handle: FramebufferHandle) ImageHandle {
    return v_tab.getSurfaceImage(framebuffer_handle);
}

/// Returns the surface image view of the swapchain.
pub inline fn getSurfaceImageView(framebuffer_handle: FramebufferHandle) ImageViewHandle {
    return v_tab.getSurfaceImageView(framebuffer_handle);
}

/// Returns the color format of the swapchain.
pub inline fn getSurfaceColorFormat() ImageFormat {
    return v_tab.getSurfaceColorFormat();
}

/// Returns the depth format of the swapchain.
pub inline fn getSurfaceDepthFormat() ImageFormat {
    return v_tab.getSurfaceDepthFormat();
}

/// Returns the stride of a uniform buffer.
pub inline fn getUniformAlignment() u32 {
    return v_tab.getUniformAlignment();
}

/// Returns the maximum number of frames in flight.
/// This is the number of frames that can be rendered simultaneously.
pub inline fn getMaxFramesInFlight() u32 {
    return v_tab.getMaxFramesInFlight();
}

/// Returns the current frame in flight.
/// This is the index of the current frame being rendered.
/// This value is in the range [0, maxFramesInFlight).
pub inline fn getCurrentFrameInFlight() u32 {
    return v_tab.getCurrentFrameInFlight();
}

/// Creates a framebuffer.
pub fn createFramebuffer(window_handle: platform.WindowHandle) !FramebufferHandle {
    return try v_tab.createFramebuffer(window_handle);
}

/// Destroys a framebuffer.
pub inline fn destroyFramebuffer(handle: FramebufferHandle) void {
    v_tab.destroyFramebuffer(handle);
}

/// Creates an image.
pub fn createImage(options: ImageOptions) !ImageHandle {
    return try v_tab.createImage(options);
}

/// Destroys an image.
pub inline fn destroyImage(handle: ImageHandle) void {
    v_tab.destroyImage(handle);
}

/// Creates an image view.
pub fn createImageView(
    image_handle: ImageHandle,
    options: ImageViewOptions,
) !ImageViewHandle {
    return try v_tab.createImageView(image_handle, options);
}

/// Destroys an image view.
pub inline fn destroyImageView(handle: ImageViewHandle) void {
    v_tab.destroyImageView(handle);
}

/// Creates a shader from a loader.
pub fn createShader(reader: std.io.AnyReader, options: ShaderOptions) !ShaderHandle {
    return try v_tab.createShader(reader, options);
}

/// Creates a shader from memory.
pub fn createShaderFromMemory(data: []const u8, options: ShaderOptions) !ShaderHandle {
    var stream = std.io.fixedBufferStream(data);
    return try v_tab.createShader(stream.reader().any(), options);
}

/// Destroys a shader.
pub inline fn destroyShader(handle: ShaderHandle) void {
    v_tab.destroyShader(handle);
}

/// Creates a program from vertex and fragment shaders.
pub inline fn createProgram(
    vertex_shader: ShaderHandle,
    fragment_shader: ShaderHandle,
    options: ProgramOptions,
) !ProgramHandle {
    return try v_tab.createProgram(
        vertex_shader,
        fragment_shader,
        options,
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
    return try v_tab.createTexture(stream.reader().any(), @intCast(data.len), options);
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

pub inline fn nameHandle(name: []const u8) NameHandle {
    return .{
        .handle = std.hash.Fnv1a_64.hash(name),
    };
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

/// Begins a render pass.
pub inline fn beginRenderPass(framebuffer_handle: FramebufferHandle, options: RenderPassOptions) !bool {
    return v_tab.beginRenderPass(framebuffer_handle, options);
}

/// Ends a render pass.
pub inline fn endRenderPass() void {
    v_tab.endRenderPass();
}

/// Sets the viewport.
pub inline fn setViewport(position: [2]u32, size: [2]u32) void {
    v_tab.setViewport(position, size);
}

/// Sets the scissor.
pub inline fn setScissor(position: [2]u32, size: [2]u32) void {
    v_tab.setScissor(position, size);
}

/// Sets the debug options.
pub inline fn setDebug(debug_options: DebugOptions) void {
    v_tab.setDebug(debug_options);
}

/// Sets the render options.
pub inline fn setRender(render_options: RenderOptions) void {
    v_tab.setRender(render_options);
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
    name: NameHandle,
    buffer: BufferHandle,
    offset: u32,
) void {
    v_tab.bindUniformBuffer(
        name,
        buffer,
        offset,
    );
}

pub inline fn bindCombinedSampler(name: NameHandle, texture: TextureHandle) void {
    v_tab.bindCombinedSampler(name, texture);
}

pub inline fn pushConstants(
    shader_stage: types.ShaderType,
    offset: u32,
    data: []const u8,
) void {
    v_tab.pushConstants(shader_stage, offset, data);
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
