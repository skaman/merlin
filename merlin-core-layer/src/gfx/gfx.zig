const std = @import("std");

const zm = @import("zmath");

const platform = @import("../platform/platform.zig");
const utils = @import("../utils.zig");
const noop = @import("noop/noop.zig");
const vulkan = @import("vulkan/vulkan.zig");

pub const log = std.log.scoped(.gfx);

pub const Options = struct {
    renderer_type: RendererType,
    app_name: []const u8,
    window_type: platform.NativeWindowHandleType,
    window: ?*anyopaque,
    display: ?*anyopaque,
    framebuffer_width: u32,
    framebuffer_height: u32,

    enable_vulkan_debug: bool = false,
};

pub const RendererType = enum {
    noop,
    vulkan,
};

pub const IndexType = enum {
    u8,
    u16,
    u32,
};

pub const DescriptorBindType = enum(u8) {
    uniform,
    combined_sampler,
};

pub const DescriptorBinding = struct {
    type: DescriptorBindType,
    binding: u32,
    size: u32,
    name: []const u8,
};

pub const DescriptorSet = struct {
    set: u32,
    bindings: []const DescriptorBinding,
};

pub const ShaderType = enum(u8) {
    vertex,
    fragment,
};

pub const ShaderInputAttribute = struct {
    attribute: VertexAttribute,
    location: u8,
};

pub const ShaderData = struct {
    type: ShaderType,
    data: []align(@alignOf(u32)) const u8,
    input_attributes: []const ShaderInputAttribute,
    descriptor_sets: []const DescriptorSet,
};

pub const VertexAttribute = enum(u8) {
    position,
    normal,
    tangent,
    bitangent,
    color_0,
    color_1,
    color_2,
    color_3,
    indices,
    weight,
    tex_coord_0,
    tex_coord_1,
    tex_coord_2,
    tex_coord_3,
    tex_coord_4,
    tex_coord_5,
    tex_coord_6,
    tex_coord_7,
};

pub const VertexAttributeType = enum(u8) {
    uint_8,
    uint_10,
    int_16,
    half,
    float,

    const SizeTable = [_][4]u8{
        [_]u8{ 1, 2, 4, 4 }, // uint_8
        [_]u8{ 4, 4, 4, 4 }, // uint_10
        [_]u8{ 2, 4, 8, 8 }, // int_16
        [_]u8{ 2, 4, 8, 8 }, // half
        [_]u8{ 4, 8, 12, 16 }, // float
    };

    pub fn getSize(self: VertexAttributeType, num: u3) u8 {
        return SizeTable[@intFromEnum(self)][num - 1];
    }
};

pub const VertexAttributeData = packed struct {
    normalized: bool,
    type: VertexAttributeType,
    num: u3,
    as_int: bool,
};

pub const VertexLayout = struct {
    const Self = @This();

    stride: u16,
    offsets: [@typeInfo(VertexAttribute).@"enum".fields.len]u16,
    attributes: [@typeInfo(VertexAttribute).@"enum".fields.len]VertexAttributeData,

    pub fn init() VertexLayout {
        var offsets: [@typeInfo(VertexAttribute).@"enum".fields.len]u16 = undefined;
        @memset(&offsets, 0);

        var attributes: [@typeInfo(VertexAttribute).@"enum".fields.len]VertexAttributeData = undefined;
        @memset(&attributes, .{ .normalized = false, .type = .uint_8, .num = 0, .as_int = false });

        return .{
            .stride = 0,
            .offsets = offsets,
            .attributes = attributes,
        };
    }

    pub fn add(self: *Self, attribute: VertexAttribute, num: u3, type_: VertexAttributeType, normalized: bool, as_int: bool) void {
        const index = @intFromEnum(attribute);
        const size = type_.getSize(num);

        self.attributes[index] = .{
            .normalized = normalized,
            .type = type_,
            .num = num,
            .as_int = as_int,
        };
        self.offsets[index] = self.stride;
        self.stride += size;
    }

    pub fn skip(self: *Self, num: u8) void {
        self.stride += num;
    }
};

pub const ModelViewProj = struct {
    model: zm.Mat align(16),
    view: zm.Mat align(16),
    proj: zm.Mat align(16),
};

pub const ShaderMagic = @as(u32, @bitCast([_]u8{ 'M', 'S', 'H', 'A' }));
pub const ShaderVersion: u8 = 1;

pub const ShaderHandle = u16;
pub const ProgramHandle = u16;
pub const VertexBufferHandle = u16;
pub const IndexBufferHandle = u16;
pub const UniformHandle = u16;
pub const TextureHandle = u16;

pub const MaxShaderHandles = 512;
pub const MaxProgramHandles = 512;
pub const MaxVertexBufferHandles = 512;
pub const MaxIndexBufferHandles = 512;
pub const MaxUniformHandles = 512;
pub const MaxTextureHandles = 512;

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    getSwapchainSize: *const fn () [2]u32,
    setFramebufferSize: *const fn (size: [2]u32) void,
    createShader: *const fn (handle: ShaderHandle, data: *const ShaderData) anyerror!void,
    destroyShader: *const fn (handle: ShaderHandle) void,
    createProgram: *const fn (handle: ProgramHandle, vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) anyerror!void,
    destroyProgram: *const fn (handle: ProgramHandle) void,
    createVertexBuffer: *const fn (handle: VertexBufferHandle, data: []const u8, layout: VertexLayout) anyerror!void,
    destroyVertexBuffer: *const fn (handle: VertexBufferHandle) void,
    createIndexBuffer: *const fn (handle: IndexBufferHandle, data: []const u8, index_type: IndexType) anyerror!void,
    destroyIndexBuffer: *const fn (handle: IndexBufferHandle) void,
    createUniformBuffer: *const fn (handle: UniformHandle, name: []const u8, size: u32) anyerror!void,
    destroyUniformBuffer: *const fn (handle: UniformHandle) void,
    updateUniformBuffer: *const fn (handle: UniformHandle, data: []const u8) anyerror!void,
    createTexture: *const fn (handle: TextureHandle, reader: std.io.AnyReader) anyerror!void,
    destroyTexture: *const fn (handle: TextureHandle) void,
    beginFrame: *const fn () anyerror!bool,
    endFrame: *const fn () anyerror!void,
    setViewport: *const fn (position: [2]u32, size: [2]u32) void,
    setScissor: *const fn (position: [2]u32, size: [2]u32) void,
    bindProgram: *const fn (program: ProgramHandle) void,
    bindVertexBuffer: *const fn (vertex_buffer: VertexBufferHandle) void,
    bindIndexBuffer: *const fn (index_buffer: IndexBufferHandle) void,
    draw: *const fn (vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void,
    drawIndexed: *const fn (index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void,
};

var g_gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var g_allocator: std.mem.Allocator = undefined;

var g_arena: std.heap.ArenaAllocator = undefined;
var g_arena_allocator: std.mem.Allocator = undefined;

var g_initialized: bool = false;
var g_renderer_type: RendererType = undefined;

var g_shader_handles: utils.HandlePool(ShaderHandle, MaxShaderHandles) = undefined;
var g_program_handles: utils.HandlePool(ProgramHandle, MaxProgramHandles) = undefined;
var g_vertex_buffer_handles: utils.HandlePool(VertexBufferHandle, MaxVertexBufferHandles) = undefined;
var g_index_buffer_handles: utils.HandlePool(IndexBufferHandle, MaxIndexBufferHandles) = undefined;
var g_uniform_handles: utils.HandlePool(UniformHandle, MaxUniformHandles) = undefined;
var g_texture_handles: utils.HandlePool(TextureHandle, MaxTextureHandles) = undefined;

var g_mvp_uniform_handle: UniformHandle = undefined;

var g_v_tab: VTab = undefined;

fn getVTab(
    renderer_type: RendererType,
) !VTab {
    switch (renderer_type) {
        RendererType.noop => {
            return VTab{
                .init = noop.init,
                .deinit = noop.deinit,
                .getSwapchainSize = noop.getSwapchainSize,
                .setFramebufferSize = noop.setFramebufferSize,
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
                .beginFrame = noop.beginFrame,
                .endFrame = noop.endFrame,
                .setViewport = noop.setViewport,
                .setScissor = noop.setScissor,
                .bindProgram = noop.bindProgram,
                .bindVertexBuffer = noop.bindVertexBuffer,
                .bindIndexBuffer = noop.bindIndexBuffer,
                .draw = noop.draw,
                .drawIndexed = noop.drawIndexed,
            };
        },
        RendererType.vulkan => {
            return VTab{
                .init = vulkan.init,
                .deinit = vulkan.deinit,
                .getSwapchainSize = vulkan.getSwapchainSize,
                .setFramebufferSize = vulkan.setFramebufferSize,
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
                .beginFrame = vulkan.beginFrame,
                .endFrame = vulkan.endFrame,
                .setViewport = vulkan.setViewport,
                .setScissor = vulkan.setScissor,
                .bindProgram = vulkan.bindProgram,
                .bindVertexBuffer = vulkan.bindVertexBuffer,
                .bindIndexBuffer = vulkan.bindIndexBuffer,
                .draw = vulkan.draw,
                .drawIndexed = vulkan.drawIndexed,
            };
        },
    }
}

pub fn init(
    options: Options,
) !void {
    log.debug("Initializing renderer", .{});

    g_v_tab = try getVTab(options.renderer_type);

    g_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = g_gpa.deinit();
    g_allocator = g_gpa.allocator();

    g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer g_arena.deinit();
    g_arena_allocator = g_arena.allocator();

    try g_v_tab.init(g_allocator, g_arena_allocator, &options);
    errdefer g_v_tab.deinit();

    g_renderer_type = options.renderer_type;

    g_shader_handles = .init();
    g_program_handles = .init();
    g_vertex_buffer_handles = .init();
    g_index_buffer_handles = .init();
    g_uniform_handles = .init();
    g_texture_handles = .init();

    g_initialized = true;

    g_mvp_uniform_handle = try createUniformBuffer("u_mvp", @sizeOf(ModelViewProj));
}

pub fn deinit() void {
    std.debug.assert(g_initialized);

    log.debug("Deinitializing renderer", .{});

    destroyUniformBuffer(g_mvp_uniform_handle);

    g_shader_handles.deinit();
    g_program_handles.deinit();
    g_vertex_buffer_handles.deinit();
    g_index_buffer_handles.deinit();
    g_uniform_handles.deinit();
    g_texture_handles.deinit();

    g_v_tab.deinit();

    g_arena.deinit();
    _ = g_gpa.deinit();

    g_initialized = false;
}

pub fn getSwapchainSize() [2]u32 {
    std.debug.assert(g_initialized);

    return g_v_tab.getSwapchainSize();
}

pub fn setFramebufferSize(size: [2]u32) void {
    std.debug.assert(g_initialized);

    g_v_tab.setFramebufferSize(size);
}

pub fn setModelViewProj(mvp: ModelViewProj) void {
    std.debug.assert(g_initialized);

    const ptr: [*]const u8 = @ptrCast(&mvp);
    updateUniformBuffer(
        g_mvp_uniform_handle,
        ptr[0..@sizeOf(ModelViewProj)],
    );
}

pub fn createShader(reader: std.io.AnyReader) !ShaderHandle {
    std.debug.assert(g_initialized);

    try utils.Serializer.checkHeader(reader, ShaderMagic, ShaderVersion);
    const shader_data = try utils.Serializer.read(
        ShaderData,
        g_arena_allocator,
        reader,
    );

    const handle = try g_shader_handles.alloc();
    errdefer g_shader_handles.free(handle);

    try g_v_tab.createShader(handle, &shader_data);
    return handle;
}

pub fn createShaderFromMemory(data: []const u8) !ShaderHandle {
    std.debug.assert(g_initialized);

    var stream = std.io.fixedBufferStream(data);
    return try createShader(stream.reader().any());
}

pub fn destroyShader(handle: ShaderHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.destroyShader(handle);
    g_shader_handles.free(handle);
}

pub fn createProgram(vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) !ProgramHandle {
    std.debug.assert(g_initialized);

    const handle = try g_program_handles.alloc();
    errdefer g_program_handles.free(handle);

    try g_v_tab.createProgram(handle, vertex_shader, fragment_shader);
    return handle;
}

pub fn destroyProgram(handle: ProgramHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.destroyProgram(handle);
    g_program_handles.free(handle);
}

pub fn createVertexBuffer(data: []const u8, layout: VertexLayout) !VertexBufferHandle {
    std.debug.assert(g_initialized);

    const handle = try g_vertex_buffer_handles.alloc();
    errdefer g_vertex_buffer_handles.free(handle);

    try g_v_tab.createVertexBuffer(handle, data, layout);
    return handle;
}

pub fn destroyVertexBuffer(handle: VertexBufferHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.destroyVertexBuffer(handle);
    g_vertex_buffer_handles.free(handle);
}

pub fn createIndexBuffer(data: []const u8, index_type: IndexType) !IndexBufferHandle {
    std.debug.assert(g_initialized);

    const handle = try g_index_buffer_handles.alloc();
    errdefer g_index_buffer_handles.free(handle);

    try g_v_tab.createIndexBuffer(handle, data, index_type);
    return handle;
}

pub fn destroyIndexBuffer(handle: IndexBufferHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.destroyIndexBuffer(handle);
    g_index_buffer_handles.free(handle);
}

pub fn createUniformBuffer(name: []const u8, size: u32) !UniformHandle {
    std.debug.assert(g_initialized);

    const handle = try g_uniform_handles.alloc();
    errdefer g_uniform_handles.free(handle);

    try g_v_tab.createUniformBuffer(handle, name, size);
    return handle;
}

pub fn destroyUniformBuffer(handle: UniformHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.destroyUniformBuffer(handle);
    g_uniform_handles.free(handle);
}

pub fn updateUniformBuffer(handle: UniformHandle, data: []const u8) void {
    std.debug.assert(g_initialized);

    g_v_tab.updateUniformBuffer(handle, data) catch |err| {
        log.err("Failed to update uniform buffer: {}", .{err});
    };
}

pub fn createTexture(reader: std.io.AnyReader) !TextureHandle {
    std.debug.assert(g_initialized);

    const handle = try g_texture_handles.alloc();
    errdefer g_texture_handles.free(handle);

    try g_v_tab.createTexture(handle, reader);
    return handle;
}

pub fn createTextureFromFilePath(path: []const u8) !TextureHandle {
    std.debug.assert(g_initialized);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try createTexture(file.reader().any());
}

pub fn destroyTexture(handle: TextureHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.destroyTexture(handle);
    g_texture_handles.free(handle);
}

pub fn beginFrame() !bool {
    std.debug.assert(g_initialized);

    return g_v_tab.beginFrame();
}

pub fn endFrame() !void {
    std.debug.assert(g_initialized);

    const result = g_v_tab.endFrame();
    _ = g_arena.reset(.retain_capacity);
    return result;
}

pub fn setViewport(position: [2]u32, size: [2]u32) void {
    std.debug.assert(g_initialized);

    g_v_tab.setViewport(position, size);
}

pub fn setScissor(position: [2]u32, size: [2]u32) void {
    std.debug.assert(g_initialized);

    g_v_tab.setScissor(position, size);
}

pub fn bindProgram(handle: ProgramHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.bindProgram(handle);
}

pub fn bindVertexBuffer(handle: VertexBufferHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.bindVertexBuffer(handle);
}

pub fn bindIndexBuffer(handle: IndexBufferHandle) void {
    std.debug.assert(g_initialized);

    g_v_tab.bindIndexBuffer(handle);
}

pub fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    std.debug.assert(g_initialized);

    g_v_tab.draw(
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    std.debug.assert(g_initialized);

    g_v_tab.drawIndexed(
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
