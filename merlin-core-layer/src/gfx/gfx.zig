const std = @import("std");

const platform = @import("../platform/platform.zig");
const utils = @import("../utils.zig");
const noop = @import("noop.zig");
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

pub const Position = struct {
    x: f32,
    y: f32,
};

pub const Size = struct {
    width: f32,
    height: f32,
};

pub const Rect = struct {
    position: Position,
    size: Size,
};

pub const IndexType = enum {
    u8,
    u16,
    u32,
};

pub const ShaderType = enum(u8) {
    vertex,
    fragment,
};

pub const Attribute = enum(u8) {
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

pub const AttributeType = enum(u8) {
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

    pub fn getSize(self: AttributeType, num: u3) u8 {
        return SizeTable[@intFromEnum(self)][num - 1];
    }
};

pub const AttributeData = packed struct {
    normalized: bool,
    type: AttributeType,
    num: u3,
    as_int: bool,
};

pub const VertexLayout = struct {
    const Self = @This();

    stride: u16,
    offsets: [@typeInfo(Attribute).@"enum".fields.len]u16,
    attributes: [@typeInfo(Attribute).@"enum".fields.len]AttributeData,

    pub fn init() VertexLayout {
        var offsets: [@typeInfo(Attribute).@"enum".fields.len]u16 = undefined;
        @memset(&offsets, 0);

        var attributes: [@typeInfo(Attribute).@"enum".fields.len]AttributeData = undefined;
        @memset(&attributes, .{ .normalized = false, .type = .uint_8, .num = 0, .as_int = false });

        return .{
            .stride = 0,
            .offsets = offsets,
            .attributes = attributes,
        };
    }

    pub fn add(self: *Self, attribute: Attribute, num: u3, type_: AttributeType, normalized: bool, as_int: bool) void {
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

pub const ShaderMagic = [_]u8{ 'M', 'S', 'H', 'A' };
pub const ShaderVersion: u8 = 1;

pub const ShaderHandle = u16;
pub const ProgramHandle = u16;
pub const VertexBufferHandle = u16;
pub const IndexBufferHandle = u16;

pub const MaxShaderHandles = 512;
pub const MaxProgramHandles = 512;
pub const MaxVertexBufferHandles = 512;
pub const MaxIndexBufferHandles = 512;

const VTab = struct {
    init: *const fn (allocator: std.mem.Allocator, options: *const Options) anyerror!void,
    deinit: *const fn () void,
    getSwapchainSize: *const fn () Size,
    setViewSize: *const fn (width: u32, height: u32) void,
    createShader: *const fn (handle: ShaderHandle, data: []align(@alignOf(u32)) const u8, input_attributes: []?Attribute) anyerror!void,
    destroyShader: *const fn (handle: ShaderHandle) void,
    createProgram: *const fn (handle: ProgramHandle, vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) anyerror!void,
    destroyProgram: *const fn (handle: ProgramHandle) void,
    createVertexBuffer: *const fn (handle: VertexBufferHandle, data: [*]const u8, size: u32, layout: VertexLayout) anyerror!void,
    destroyVertexBuffer: *const fn (handle: VertexBufferHandle) void,
    createIndexBuffer: *const fn (handle: IndexBufferHandle, data: [*]const u8, size: u32, index_type: IndexType) anyerror!void,
    destroyIndexBuffer: *const fn (handle: IndexBufferHandle) void,
    beginFrame: *const fn () anyerror!bool,
    endFrame: *const fn () anyerror!void,
    setViewport: *const fn (viewport: Rect) void,
    setScissor: *const fn (scissor: Rect) void,
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

var g_renderer_type: RendererType = undefined;

var g_shader_handles: utils.HandlePool(ShaderHandle, MaxShaderHandles) = .init();
var g_program_handles: utils.HandlePool(ProgramHandle, MaxProgramHandles) = .init();
var g_vertex_buffer_handles: utils.HandlePool(VertexBufferHandle, MaxVertexBufferHandles) = .init();
var g_index_buffer_handles: utils.HandlePool(IndexBufferHandle, MaxIndexBufferHandles) = .init();

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
                .setViewSize = noop.setViewSize,
                .createShader = noop.createShader,
                .destroyShader = noop.destroyShader,
                .createProgram = noop.createProgram,
                .destroyProgram = noop.destroyProgram,
                .createVertexBuffer = noop.createVertexBuffer,
                .destroyVertexBuffer = noop.destroyVertexBuffer,
                .createIndexBuffer = noop.createIndexBuffer,
                .destroyIndexBuffer = noop.destroyIndexBuffer,
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
                .setViewSize = vulkan.setViewSize,
                .createShader = vulkan.createShader,
                .destroyShader = vulkan.destroyShader,
                .createProgram = vulkan.createProgram,
                .destroyProgram = vulkan.destroyProgram,
                .createVertexBuffer = vulkan.createVertexBuffer,
                .destroyVertexBuffer = vulkan.destroyVertexBuffer,
                .createIndexBuffer = vulkan.createIndexBuffer,
                .destroyIndexBuffer = vulkan.destroyIndexBuffer,
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

    try g_v_tab.init(g_allocator, &options);
    errdefer g_v_tab.deinit();

    g_renderer_type = options.renderer_type;
}

pub fn deinit() void {
    log.debug("Deinitializing renderer", .{});

    g_v_tab.deinit();

    g_arena.deinit();
    _ = g_gpa.deinit();
}

pub fn getSwapchainSize() Size {
    return g_v_tab.getSwapchainSize();
}

pub fn setViewSize(width: u32, height: u32) void {
    g_v_tab.setViewSize(width, height);
}

pub fn createShader(reader: anytype) !ShaderHandle {
    var magic: [4]u8 = undefined;
    _ = try reader.readAll(&magic);
    if (!std.mem.eql(u8, &ShaderMagic, &magic)) {
        return error.InvalidMagic;
    }

    const version = try reader.readInt(u8, .little);
    if (version != ShaderVersion) {
        return error.InvalidVersion;
    }

    const shader_type = try reader.readEnum(ShaderType, .little);

    const data_len = try reader.readInt(u32, .little);
    const shader_data = try g_arena_allocator.alignedAlloc(
        u8,
        @alignOf(u32),
        @intCast(data_len),
    );

    const data_read = try reader.readAll(shader_data);
    if (data_read != data_len) {
        return error.InvalidData;
    }

    var input_attributes: []?Attribute = undefined;
    if (shader_type == .vertex) {
        const input_attributes_len = try reader.readInt(u8, .little);
        input_attributes = try g_arena_allocator.alloc(
            ?Attribute,
            @intCast(input_attributes_len),
        );

        for (0..input_attributes_len) |i| {
            const exists = try reader.readInt(u8, .little);
            if (exists == 0) {
                input_attributes[i] = null;
                continue;
            }

            input_attributes[i] = try reader.readEnum(Attribute, .little);
        }
    } else {
        input_attributes = &[_]?Attribute{};
    }

    const handle = try g_shader_handles.alloc();
    errdefer g_shader_handles.free(handle);

    try g_v_tab.createShader(handle, shader_data, input_attributes);
    return handle;
}

pub fn createShaderFromMemory(data: []const u8) !ShaderHandle {
    var stream = std.io.fixedBufferStream(data);
    return try createShader(stream.reader());
}

pub fn destroyShader(handle: ShaderHandle) void {
    g_v_tab.destroyShader(handle);
    g_shader_handles.free(handle);
}

pub fn createProgram(vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) !ProgramHandle {
    const handle = try g_program_handles.alloc();
    errdefer g_program_handles.free(handle);

    try g_v_tab.createProgram(handle, vertex_shader, fragment_shader);
    return handle;
}

pub fn destroyProgram(handle: ProgramHandle) void {
    g_v_tab.destroyProgram(handle);
    g_program_handles.free(handle);
}

pub fn createVertexBuffer(data: [*]const u8, size: u32, layout: VertexLayout) !VertexBufferHandle {
    const handle = try g_vertex_buffer_handles.alloc();
    errdefer g_vertex_buffer_handles.free(handle);

    try g_v_tab.createVertexBuffer(handle, data, size, layout);
    return handle;
}

pub fn destroyVertexBuffer(handle: VertexBufferHandle) void {
    g_v_tab.destroyVertexBuffer(handle);
    g_vertex_buffer_handles.free(handle);
}

pub fn createIndexBuffer(data: [*]const u8, size: u32, index_type: IndexType) !IndexBufferHandle {
    const handle = try g_index_buffer_handles.alloc();
    errdefer g_index_buffer_handles.free(handle);

    try g_v_tab.createIndexBuffer(handle, data, size, index_type);
    return handle;
}

pub fn destroyIndexBuffer(handle: IndexBufferHandle) void {
    g_v_tab.destroyIndexBuffer(handle);
    g_index_buffer_handles.free(handle);
}

pub fn beginFrame() !bool {
    return g_v_tab.beginFrame();
}

pub fn endFrame() !void {
    const result = g_v_tab.endFrame();
    _ = g_arena.reset(.retain_capacity);
    return result;
}

pub fn setViewport(viewport: Rect) void {
    g_v_tab.setViewport(viewport);
}

pub fn setScissor(scissor: Rect) void {
    g_v_tab.setScissor(scissor);
}

pub fn bindProgram(handle: ProgramHandle) void {
    g_v_tab.bindProgram(handle);
}

pub fn bindVertexBuffer(handle: VertexBufferHandle) void {
    g_v_tab.bindVertexBuffer(handle);
}

pub fn bindIndexBuffer(handle: IndexBufferHandle) void {
    g_v_tab.bindIndexBuffer(handle);
}

pub fn draw(vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
    g_v_tab.draw(vertex_count, instance_count, first_vertex, first_instance);
}

pub fn drawIndexed(index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
    g_v_tab.drawIndexed(index_count, instance_count, first_index, vertex_offset, first_instance);
}
