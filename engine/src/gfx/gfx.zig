const std = @import("std");

const shared = @import("shared");

const c = @import("../c.zig").c;
const noop = @import("noop.zig");
const vulkan = @import("vulkan/vulkan.zig");

pub const GraphicsContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: GraphicsOptions,
};

pub const GraphicsOptions = struct {
    renderer_type: RendererType,
    app_name: [:0]const u8,
    window: *c.GLFWwindow,

    enable_vulkan_debug: bool = false,
};

pub const RendererType = enum {
    noop,
    vulkan,
};

pub const ShaderHandle = u16;
pub const ProgramHandle = u16;
pub const VertexBufferHandle = u16;
pub const IndexBufferHandle = u16;

pub const MaxShaderHandles = 512;
pub const MaxProgramHandles = 512;
pub const MaxVertexBufferHandles = 512;
pub const MaxIndexBufferHandles = 512;

fn HandlePool(comptime THandle: type, comptime size: comptime_int) type {
    return struct {
        const Self = @This();

        free_list: [size]THandle,
        free_count: u32 = size,

        pub fn init() Self {
            var self: Self = .{
                .free_list = undefined,
                .free_count = size,
            };

            for (0..size) |i| {
                self.free_list[i] = @intCast((size - 1) - i);
            }

            return self;
        }

        pub fn alloc(self: *Self) !THandle {
            if (self.free_count == 0) {
                return error.NoAvailableHandles;
            }

            self.free_count -= 1;
            return self.free_list[self.free_count];
        }

        pub fn free(self: *Self, handle: THandle) void {
            self.free_list[self.free_count] = handle;
            self.free_count += 1;
        }
    };
}

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

const RendererVTab = struct {
    init: *const fn (graphics_ctx: *const GraphicsContext) anyerror!void,
    deinit: *const fn () void,
    getSwapchainSize: *const fn () Size,
    invalidateFramebuffer: *const fn () void,
    createShader: *const fn (handle: ShaderHandle, *const shared.ShaderData) anyerror!void,
    destroyShader: *const fn (handle: ShaderHandle) void,
    createProgram: *const fn (handle: ProgramHandle, vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) anyerror!void,
    destroyProgram: *const fn (handle: ProgramHandle) void,
    createVertexBuffer: *const fn (handle: VertexBufferHandle, data: [*]const u8, size: u32, layout: shared.VertexLayout) anyerror!void,
    destroyVertexBuffer: *const fn (handle: VertexBufferHandle) void,
    createIndexBuffer: *const fn (handle: IndexBufferHandle, data: [*]const u8, size: u32) anyerror!void,
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

var g_allocator: std.mem.Allocator = undefined;
var g_arena_allocator: std.mem.Allocator = undefined;
var g_renderer_type: RendererType = undefined;

var g_shader_handles: HandlePool(ShaderHandle, MaxShaderHandles) = .init();
var g_program_handles: HandlePool(ProgramHandle, MaxProgramHandles) = .init();
var g_vertex_buffer_handles: HandlePool(VertexBufferHandle, MaxVertexBufferHandles) = .init();
var g_index_buffer_handles: HandlePool(IndexBufferHandle, MaxIndexBufferHandles) = .init();

var g_renderer_v_tab: RendererVTab = undefined;

fn getRendererVTab(
    renderer_type: RendererType,
) !RendererVTab {
    switch (renderer_type) {
        RendererType.noop => {
            return RendererVTab{
                .init = noop.init,
                .deinit = noop.deinit,
                .getSwapchainSize = noop.getSwapchainSize,
                .invalidateFramebuffer = noop.invalidateFramebuffer,
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
            return RendererVTab{
                .init = vulkan.init,
                .deinit = vulkan.deinit,
                .getSwapchainSize = vulkan.getSwapchainSize,
                .invalidateFramebuffer = vulkan.invalidateFramebuffer,
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
    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: GraphicsOptions,
) !void {
    std.log.debug("Initializing renderer...", .{});

    const graphics_context = GraphicsContext{
        .allocator = allocator,
        .arena_allocator = arena_allocator,
        .options = options,
    };

    g_renderer_v_tab = try getRendererVTab(options.renderer_type);

    try g_renderer_v_tab.init(&graphics_context);

    g_allocator = allocator;
    g_arena_allocator = arena_allocator;
    g_renderer_type = options.renderer_type;
}

pub fn deinit() void {
    std.log.debug("Deinitializing renderer...", .{});
    g_renderer_v_tab.deinit();
}

pub fn getSwapchainSize() Size {
    return g_renderer_v_tab.getSwapchainSize();
}

pub fn invalidateFramebuffer() void {
    g_renderer_v_tab.invalidateFramebuffer();
}

pub fn createShader(data: *const shared.ShaderData) !ShaderHandle {
    const handle = try g_shader_handles.alloc();
    errdefer g_shader_handles.free(handle);

    try g_renderer_v_tab.createShader(handle, data);
    return handle;
}

//pub fn createShaderUnaligned(data: []const u8) !ShaderHandle {
//    const aligned_data = try context.arena_allocator.alignedAlloc(
//        u8,
//        @alignOf(u32),
//        data.len,
//    );
//    std.mem.copyForwards(u8, aligned_data, data);
//    return try createShader(aligned_data);
//}

pub fn destroyShader(handle: ShaderHandle) void {
    g_renderer_v_tab.destroyShader(handle);
    g_shader_handles.free(handle);
}

pub fn createProgram(vertex_shader: ShaderHandle, fragment_shader: ShaderHandle) !ProgramHandle {
    const handle = try g_program_handles.alloc();
    errdefer g_program_handles.free(handle);

    try g_renderer_v_tab.createProgram(handle, vertex_shader, fragment_shader);
    return handle;
}

pub fn destroyProgram(handle: ProgramHandle) void {
    g_renderer_v_tab.destroyProgram(handle);
    g_program_handles.free(handle);
}

pub fn createIndexBuffer(data: [*]const u8, size: u32) !IndexBufferHandle {
    const handle = try g_index_buffer_handles.alloc();
    errdefer g_index_buffer_handles.free(handle);

    try g_renderer_v_tab.createIndexBuffer(handle, data, size);
    return handle;
}

pub fn destroyIndexBuffer(handle: IndexBufferHandle) void {
    g_renderer_v_tab.destroyIndexBuffer(handle);
    g_index_buffer_handles.free(handle);
}

pub fn createVertexBuffer(data: [*]const u8, size: u32, layout: shared.VertexLayout) !VertexBufferHandle {
    const handle = try g_vertex_buffer_handles.alloc();
    errdefer g_vertex_buffer_handles.free(handle);

    try g_renderer_v_tab.createVertexBuffer(handle, data, size, layout);
    return handle;
}

pub fn destroyVertexBuffer(handle: VertexBufferHandle) void {
    g_renderer_v_tab.destroyVertexBuffer(handle);
    g_vertex_buffer_handles.free(handle);
}

pub fn beginFrame() !bool {
    return g_renderer_v_tab.beginFrame();
}

pub fn endFrame() !void {
    return g_renderer_v_tab.endFrame();
}

pub fn setViewport(viewport: Rect) void {
    g_renderer_v_tab.setViewport(viewport);
}

pub fn setScissor(scissor: Rect) void {
    g_renderer_v_tab.setScissor(scissor);
}

pub fn bindProgram(handle: ProgramHandle) void {
    g_renderer_v_tab.bindProgram(handle);
}

pub fn bindVertexBuffer(handle: VertexBufferHandle) void {
    g_renderer_v_tab.bindVertexBuffer(handle);
}

pub fn bindIndexBuffer(handle: IndexBufferHandle) void {
    g_renderer_v_tab.bindIndexBuffer(handle);
}

pub fn draw(vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
    g_renderer_v_tab.draw(vertex_count, instance_count, first_vertex, first_instance);
}

pub fn drawIndexed(index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) void {
    g_renderer_v_tab.drawIndexed(index_count, instance_count, first_index, vertex_offset, first_instance);
}
