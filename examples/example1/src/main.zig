const std = @import("std");

const mcl = @import("merlin_core_layer");
const gfx = mcl.gfx;
const zm = mcl.zmath;
const platform = mcl.platform;

const frag_shader_code = @embedFile("shader.frag.bin");
const vert_shader_code = @embedFile("shader.vert.bin");

const Vertices = [_][5]f32{
    [_]f32{ -0.5, -0.5, 1.0, 0.0, 0.0 },
    [_]f32{ 0.5, -0.5, 0.0, 1.0, 0.0 },
    [_]f32{ 0.5, 0.5, 0.0, 0.0, 1.0 },
    [_]f32{ -0.5, 0.5, 1.0, 1.0, 1.0 },
};

const Indices = [_]u16{
    0, 1, 2,
    2, 3, 0,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    try mcl.init(
        allocator,
        arena_allocator,
        .{
            .window_title = "Example 1",
            .enable_vulkan_debug = true,
        },
    );
    defer mcl.deinit();

    const vert_shader_handle = try gfx.createShaderFromMemory(vert_shader_code);
    defer gfx.destroyShader(vert_shader_handle);

    const frag_shader_handle = try gfx.createShaderFromMemory(frag_shader_code);
    defer gfx.destroyShader(frag_shader_handle);

    const program_handle = try gfx.createProgram(vert_shader_handle, frag_shader_handle);
    defer gfx.destroyProgram(program_handle);

    var vertex_layout = gfx.VertexLayout.init();
    vertex_layout.add(.position, 2, .float, false, false);
    vertex_layout.add(.color_0, 3, .float, false, false);

    const vertex_buffer_handle = try gfx.createVertexBuffer(
        std.mem.sliceAsBytes(&Vertices).ptr,
        Vertices.len * @sizeOf(@TypeOf(Vertices)),
        vertex_layout,
    );
    defer gfx.destroyVertexBuffer(vertex_buffer_handle);

    const index_buffer_handle = try gfx.createIndexBuffer(
        std.mem.sliceAsBytes(&Indices).ptr,
        Indices.len * @sizeOf(@TypeOf(Indices)),
        .u16,
    );
    defer gfx.destroyIndexBuffer(index_buffer_handle);

    while (!platform.shouldCloseDefaultWindow()) {
        platform.pollEvents();

        const window_size = platform.getDefaultWindowFramebufferSize();
        gfx.setViewSize(window_size[0], window_size[1]);

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        const swapchain_size = gfx.getSwapchainSize();

        const aspect_ratio = swapchain_size.width / swapchain_size.height;
        const object_to_world = zm.rotationY(0);
        const world_to_view = zm.lookAtRh(
            zm.f32x4(3.0, 3.0, 3.0, 1.0), // eye position
            zm.f32x4(0.0, 0.0, 0.0, 1.0), // focus point
            zm.f32x4(0.0, 1.0, 0.0, 0.0), // up direction ('w' coord is zero because this is a vector not a point)
        );
        const view_to_clip = zm.perspectiveFovRh(0.25 * std.math.pi, aspect_ratio, 0.1, 20.0);

        const object_to_view = zm.mul(object_to_world, world_to_view);
        const object_to_clip = zm.mul(object_to_view, view_to_clip);
        _ = object_to_clip;

        gfx.setViewport(.{ .position = .{ .x = 0, .y = 0 }, .size = swapchain_size });
        gfx.setScissor(.{ .position = .{ .x = 0, .y = 0 }, .size = swapchain_size });
        gfx.bindProgram(program_handle);
        gfx.bindVertexBuffer(vertex_buffer_handle);
        gfx.bindIndexBuffer(index_buffer_handle);
        gfx.drawIndexed(6, 1, 0, 0, 0);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };

        _ = arena.reset(.retain_capacity);

        //break;
    }
}
