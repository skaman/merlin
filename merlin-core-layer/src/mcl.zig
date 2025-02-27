const std = @import("std");

pub const zmath = @import("zmath");

pub const gfx = @import("gfx/gfx.zig");
pub const platform = @import("platform/platform.zig");

pub const Options = struct {
    app_name: []const u8 = "Merlin",
    window_title: []const u8 = "Merlin",
    window_width: u32 = 800,
    window_height: u32 = 600,
    enable_vulkan_debug: bool = false,
};

pub fn init(
    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: Options,
) !void {
    try platform.init(
        allocator,
        arena_allocator,
        .{
            .type = .glfw,
            .window = .{
                .width = options.window_width,
                .height = options.window_height,
                .title = options.window_title,
            },
        },
    );
    errdefer platform.deinit();

    const framebuffer_size = platform.getDefaultWindowFramebufferSize();

    try gfx.init(
        allocator,
        arena_allocator,
        .{
            .renderer_type = .vulkan,
            .app_name = options.app_name,
            .window_type = platform.getNativeWindowHandleType(),
            .window = platform.getNativeDefaultWindowHandle(),
            .display = platform.getNativeDefaultDisplayHandle(),
            .framebuffer_width = framebuffer_size[0],
            .framebuffer_height = framebuffer_size[1],
            .enable_vulkan_debug = options.enable_vulkan_debug,
        },
    );
    errdefer gfx.deinit();
}

pub fn deinit() void {
    gfx.deinit();
    platform.deinit();
}
