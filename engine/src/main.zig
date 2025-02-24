const std = @import("std");

const shared = @import("shared");

const c = @import("c.zig").c;
const gfx = @import("gfx/gfx.zig");

const frag_shader_code = @embedFile("shader.frag.z3sh");
const vert_shader_code = @embedFile("shader.vert.z3sh");

pub fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    std.log.err("{s}", .{description});
}

pub fn glfwFramebufferSizeCallback(_: ?*c.GLFWwindow, _: c_int, _: c_int) callconv(.c) void {
    gfx.invalidateFramebuffer();
}

pub fn main() !void {
    _ = c.glfwSetErrorCallback(&glfwErrorCallback);

    if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;
    defer c.glfwTerminate();

    if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    const window = c.glfwCreateWindow(
        600,
        600,
        "z3dfx",
        null,
        null,
    ) orelse return error.WindowInitFailed;
    defer c.glfwDestroyWindow(window);

    _ = c.glfwSetFramebufferSizeCallback(window, &glfwFramebufferSizeCallback);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    try gfx.init(
        allocator,
        arena_allocator,
        .{
            .renderer_type = .vulkan,
            .app_name = "TEST APP",
            .window = window,
            .enable_vulkan_debug = true,
        },
    );
    defer gfx.deinit();

    // VERTEX SHADER
    var vert_shader_stream = std.io.fixedBufferStream(vert_shader_code);
    var vert_shader_data = try shared.ShaderData.read(allocator, vert_shader_stream.reader());
    defer vert_shader_data.deinit();

    const vert_shader_handle = try gfx.createShader(&vert_shader_data);
    defer gfx.destroyShader(vert_shader_handle);

    // FRAGMENT SHADER
    var frag_shader_stream = std.io.fixedBufferStream(frag_shader_code);
    var frag_shader_data = try shared.ShaderData.read(allocator, frag_shader_stream.reader());
    defer frag_shader_data.deinit();

    const frag_shader_handle = try gfx.createShader(&frag_shader_data);
    defer gfx.destroyShader(frag_shader_handle);

    const program_handle = try gfx.createProgram(vert_shader_handle, frag_shader_handle);
    defer gfx.destroyProgram(program_handle);

    var vertex_layout = shared.VertexLayout.init();
    vertex_layout.add(.position, 2, .float, false, false);
    vertex_layout.add(.color_0, 3, .float, false, false);

    const vertices = [_][5]f32{
        [_]f32{ -0.5, -0.5, 1.0, 0.0, 0.0 },
        [_]f32{ 0.5, -0.5, 0.0, 1.0, 0.0 },
        [_]f32{ 0.5, 0.5, 0.0, 0.0, 1.0 },
        [_]f32{ -0.5, 0.5, 1.0, 1.0, 1.0 },
    };

    const indices = [_]u16{
        0, 1, 2,
        2, 3, 0,
    };

    const vertex_buffer_handle = try gfx.createVertexBuffer(
        std.mem.sliceAsBytes(&vertices).ptr,
        vertices.len * @sizeOf(@TypeOf(vertices)),
        vertex_layout,
    );
    defer gfx.destroyVertexBuffer(vertex_buffer_handle);

    const index_buffer_handle = try gfx.createIndexBuffer(
        std.mem.sliceAsBytes(&indices).ptr,
        indices.len * @sizeOf(@TypeOf(indices)),
    );
    defer gfx.destroyIndexBuffer(index_buffer_handle);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        const swapchain_size = gfx.getSwapchainSize();

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
