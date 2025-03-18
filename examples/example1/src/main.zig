const std = @import("std");

const gfx = @import("merlin_gfx");
const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;
const zm = @import("zmath");

const Vertices = [_][8]f32{
    [_]f32{ -0.5, -0.5, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0 },
    [_]f32{ 0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0 },
    [_]f32{ 0.5, 0.5, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0 },
    [_]f32{ -0.5, 0.5, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0 },

    [_]f32{ -0.5, -0.5, -0.5, 1.0, 0.0, 0.0, 1.0, 0.0 },
    [_]f32{ 0.5, -0.5, -0.5, 0.0, 1.0, 0.0, 0.0, 0.0 },
    [_]f32{ 0.5, 0.5, -0.5, 0.0, 0.0, 1.0, 0.0, 1.0 },
    [_]f32{ -0.5, 0.5, -0.5, 1.0, 1.0, 1.0, 1.0, 1.0 },
};

const Indices = [_]u16{
    0, 1, 2, 2, 3, 0,
    4, 5, 6, 6, 7, 4,
};

fn getAssetPath(allocator: std.mem.Allocator, asset_name: []const u8) ![]const u8 {
    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_path);

    return try std.fs.path.join(allocator, &[_][]const u8{
        exe_path,
        std.mem.bytesAsSlice(u8, "assets"),
        asset_name,
    });
}

fn loadShader(allocator: std.mem.Allocator, filename: []const u8) !gfx.ShaderHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file_loader = utils.loaders.ShaderFileLoader{ .filename = path };
    const loader = utils.loaders.ShaderLoader.from(&file_loader, utils.loaders.ShaderFileLoader);
    return try gfx.createShader(loader);
}

fn loadTexture(allocator: std.mem.Allocator, filename: []const u8) !gfx.TextureHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file_loader = utils.loaders.TextureFileLoader{ .filename = path };
    const loader = utils.loaders.TextureLoader.from(&file_loader, utils.loaders.TextureFileLoader);
    return try gfx.createTexture(loader);
}

fn loadVertexBuffer(allocator: std.mem.Allocator, filename: []const u8) !gfx.TextureHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file_loader = utils.loaders.VertexBufferFileLoader{ .filename = path };
    const loader = utils.loaders.VertexBufferLoader.from(&file_loader, utils.loaders.VertexBufferFileLoader);
    return try gfx.createVertexBuffer(loader);
}

fn loadIndexBuffer(allocator: std.mem.Allocator, filename: []const u8) !gfx.TextureHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file_loader = utils.loaders.IndexBufferFileLoader{ .filename = path };
    const loader = utils.loaders.IndexBufferLoader.from(&file_loader, utils.loaders.IndexBufferFileLoader);
    return try gfx.createIndexBuffer(loader);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    try platform.init(
        allocator,
        .{
            .type = .glfw,
            .window = .{
                .width = 800,
                .height = 600,
                .title = "Example 1",
            },
        },
    );
    defer platform.deinit();

    try gfx.init(
        allocator,
        .{
            .renderer_type = .vulkan,
            .enable_vulkan_debug = true,
        },
    );
    defer gfx.deinit();

    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_path);

    const vert_shader_handle = try loadShader(allocator, "shader.vert.bin");
    defer gfx.destroyShader(vert_shader_handle);

    const frag_shader_handle = try loadShader(allocator, "shader.frag.bin");
    defer gfx.destroyShader(frag_shader_handle);

    const program_handle = try gfx.createProgram(vert_shader_handle, frag_shader_handle);
    defer gfx.destroyProgram(program_handle);

    const sampler_handle = try gfx.createCombinedSampler("u_tex_sampler");
    defer gfx.destroyCombinedSampler(sampler_handle);

    const texture_handle = try loadTexture(allocator, "uv_texture.ktx");
    defer gfx.destroyTexture(texture_handle);

    const vertex_buffer_handle = try loadVertexBuffer(allocator, "Box/vertex.0.bin");
    defer gfx.destroyVertexBuffer(vertex_buffer_handle);

    const index_buffer_handle = try loadIndexBuffer(allocator, "Box/index.0.bin");
    defer gfx.destroyIndexBuffer(index_buffer_handle);

    //var vertex_layout = gfx_types.VertexLayout.init();
    //vertex_layout.add(.position, 3, .f32, false);
    //vertex_layout.add(.color_0, 3, .f32, false);
    //vertex_layout.add(.tex_coord_0, 2, .f32, false);

    //var vertex_buffer_loader = utils.loaders.VertexBufferMemoryLoader{
    //    .layout = vertex_layout,
    //    .data = std.mem.sliceAsBytes(&Vertices),
    //};

    //const vertex_buffer_handle = try gfx.createVertexBuffer(
    //    utils.loaders.VertexBufferLoader.from(&vertex_buffer_loader, utils.loaders.VertexBufferMemoryLoader),
    //);
    //defer gfx.destroyVertexBuffer(vertex_buffer_handle);

    //var index_buffer_loader = utils.loaders.IndexBufferMemoryLoader{
    //    .index_type = .u16,
    //    .data = std.mem.sliceAsBytes(&Indices),
    //};

    //const index_buffer_handle = try gfx.createIndexBuffer(
    //    utils.loaders.IndexBufferLoader.from(&index_buffer_loader, utils.loaders.IndexBufferMemoryLoader),
    //);
    //defer gfx.destroyIndexBuffer(index_buffer_handle);

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
        gfx.bindTexture(texture_handle, sampler_handle);
        gfx.drawIndexed(36, 1, 0, 0, 0);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };
    }
}
