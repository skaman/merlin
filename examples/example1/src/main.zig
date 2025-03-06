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
    try mcl.init(
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
        std.mem.sliceAsBytes(&Vertices),
        vertex_layout,
    );
    defer gfx.destroyVertexBuffer(vertex_buffer_handle);

    const index_buffer_handle = try gfx.createIndexBuffer(
        std.mem.sliceAsBytes(&Indices),
        .u16,
    );
    defer gfx.destroyIndexBuffer(index_buffer_handle);

    const start_time = std.time.microTimestamp();
    var last_current_time = start_time;

    var fps_counter: u32 = 0;
    var fps_timer: f32 = 0.0;

    while (!platform.shouldCloseDefaultWindow()) {
        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        fps_counter += 1;
        fps_timer += delta_time;
        if (fps_timer >= 1.0) {
            std.debug.print("FPS: {d}\n", .{fps_counter});
            fps_counter = 0;
            fps_timer -= 1.0;
        }

        const window_size = platform.getDefaultWindowFramebufferSize();
        gfx.setFramebufferSize(window_size);

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        const swapchain_size = gfx.getSwapchainSize();
        const aspect_ratio = @as(f32, @floatFromInt(swapchain_size[0])) / @as(f32, @floatFromInt(swapchain_size[1]));
        const time = @as(f32, @floatFromInt(current_time - start_time)) / 1_000_000.0;

        gfx.setModelViewProj(.{
            .model = zm.rotationZ(std.math.rad_per_deg * 90.0 * time),
            .view = zm.lookAtRh(
                zm.f32x4(3.0, 3.0, 3.0, 1.0),
                zm.f32x4(0.0, 0.0, 0.0, 1.0),
                zm.f32x4(0.0, 0.0, -1.0, 0.0),
            ),
            .proj = zm.perspectiveFovRh(
                std.math.rad_per_deg * 45.0,
                aspect_ratio,
                0.1,
                20.0,
            ),
        });

        gfx.setViewport(.{ 0, 0 }, swapchain_size);
        gfx.setScissor(.{ 0, 0 }, swapchain_size);
        gfx.bindProgram(program_handle);
        gfx.bindVertexBuffer(vertex_buffer_handle);
        gfx.bindIndexBuffer(index_buffer_handle);
        gfx.drawIndexed(6, 1, 0, 0, 0);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };
    }
}
