const std = @import("std");

const c = @import("c.zig");
const z3dfx = @import("renderer/z3dfx.zig");

pub fn glfwErrorCallback(_: c_int, description: [*c]const u8) callconv(.c) void {
    std.log.err("{s}", .{description});
}

pub fn main() !void {
    _ = c.glfw.glfwSetErrorCallback(&glfwErrorCallback);

    if (c.glfw.glfwInit() != c.glfw.GLFW_TRUE) return error.GlfwInitFailed;
    defer c.glfw.glfwTerminate();

    if (c.glfw.glfwVulkanSupported() != c.glfw.GLFW_TRUE) {
        std.log.err("GLFW could not find libvulkan", .{});
        return error.NoVulkan;
    }

    c.glfw.glfwWindowHint(c.glfw.GLFW_CLIENT_API, c.glfw.GLFW_NO_API);
    const window = c.glfw.glfwCreateWindow(
        600,
        600,
        "z3dfx",
        null,
        null,
    ) orelse return error.WindowInitFailed;
    defer c.glfw.glfwDestroyWindow(window);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try z3dfx.init(allocator, .{
        .renderer_type = .vulkan,
        .app_name = "TEST APP",
        .window = window,
        .enable_vulkan_debug = true,
    });
    defer z3dfx.deinit();

    while (c.glfw.glfwWindowShouldClose(window) == c.glfw.GLFW_FALSE) {
        c.glfw.glfwPollEvents();

        // render your things here

        c.glfw.glfwPollEvents();
    }
}
