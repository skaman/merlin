const std = @import("std");

const assets = @import("merlin_assets");
const gfx = @import("merlin_gfx");
const imgui = @import("merlin_imgui");
const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;
const zm = @import("zmath");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const ModelViewProj = struct {
    model: zm.Mat align(16),
    view: zm.Mat align(16),
    proj: zm.Mat align(16),
};

const Context = struct {
    gpa_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
};

// *********************************************************************************************
// Logic
// *********************************************************************************************

pub fn init(gpa_allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator) !Context {
    return Context{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
    };
}

pub fn deinit(context: *Context) void {
    _ = context;
}

pub fn update(context: *Context, delta_time: f32) void {
    const swapchain_size = gfx.swapchainSize();

    gfx.setViewport(.{ 0, 0 }, swapchain_size);
    gfx.setScissor(.{ 0, 0 }, swapchain_size);

    _ = context;

    imgui.update(delta_time) catch |err| {
        std.log.err("Failed to render ImGui: {}", .{err});
    };
}

// *********************************************************************************************
// Main
// *********************************************************************************************

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa_allocator = gpa.allocator();
    const arena_allocator = arena.allocator();

    try platform.init(
        gpa_allocator,
        .{ .type = .glfw },
    );
    defer platform.deinit();

    const window_handle = try platform.createWindow(.{
        .width = 800,
        .height = 600,
        .title = "Example 1",
    });
    defer platform.destroyWindow(window_handle);

    try gfx.init(
        gpa_allocator,
        .{
            .renderer_type = .vulkan,
            .window_handle = window_handle,
            .enable_vulkan_debug = true,
        },
    );
    defer gfx.deinit();

    try assets.init(gpa_allocator);
    defer assets.deinit();

    try imgui.init(gpa_allocator, .{
        .window_handle = window_handle,
    });
    defer imgui.deinit();

    var context = try init(gpa_allocator, arena_allocator);
    defer deinit(&context);

    const start_time = std.time.microTimestamp();
    var last_current_time = start_time;

    while (!platform.shouldCloseWindow(window_handle)) {
        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        {
            gfx.beginDebugLabel("Frame", gfx_types.Colors.Red);
            defer gfx.endDebugLabel();

            update(&context, delta_time);
        }

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };

        _ = arena.reset(.retain_capacity);
    }
}
