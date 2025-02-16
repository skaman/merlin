const std = @import("std");

const c = @import("c.zig").c;
const z3dfx = @import("renderer/z3dfx.zig");

const frag_shader_code = @embedFile("frag.spv");
const vert_shader_code = @embedFile("vert.spv");

pub fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    std.log.err("{s}", .{description});
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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    try z3dfx.init(
        allocator,
        arena_allocator,
        .{
            .renderer_type = .vulkan,
            .app_name = "TEST APP",
            .window = window,
            .enable_vulkan_debug = true,
        },
    );
    defer z3dfx.deinit();

    const vert_shader_handle = try z3dfx.createShaderUnaligned(vert_shader_code);
    defer z3dfx.destroyShader(vert_shader_handle);

    const frag_shader_handle = try z3dfx.createShaderUnaligned(frag_shader_code);
    defer z3dfx.destroyShader(frag_shader_handle);

    const program_handle = try z3dfx.createProgram(vert_shader_handle, frag_shader_handle);
    defer z3dfx.destroyProgram(program_handle);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        c.glfwPollEvents();
        z3dfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
        };

        z3dfx.setViewport(.{ .x = 0, .y = 0, .width = 600, .height = 600 });
        z3dfx.setScissor(.{ .x = 0, .y = 0, .width = 600, .height = 600 });
        z3dfx.bindProgram(program_handle);
        z3dfx.draw(3, 1, 0, 0);

        z3dfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };

        _ = arena.reset(.retain_capacity);

        //break;
    }
}
