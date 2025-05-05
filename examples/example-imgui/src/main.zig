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

    framerate_plot_data: std.ArrayList(f32),
};

// *********************************************************************************************
// Logic
// *********************************************************************************************

pub fn init(gpa_allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator) !Context {
    return Context{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .framerate_plot_data = .init(gpa_allocator),
    };
}

pub fn deinit(context: *Context) void {
    context.framerate_plot_data.deinit();
}

pub fn update(context: *Context, delta_time: f32) !void {
    imgui.beginFrame(delta_time);

    _ = imgui.begin("Statistics", null, .{});
    imgui.text("Ciao: {d}", .{3});
    _ = imgui.button("Test", .{});

    const framerate = imgui.framerate();
    try context.framerate_plot_data.append(framerate);
    if (context.framerate_plot_data.items.len > 2000) {
        _ = context.framerate_plot_data.orderedRemove(0);
    }

    imgui.text(
        "Application average {d:.3} ms/frame ({d:.1} FPS)",
        .{
            1000.0 / framerate,
            framerate,
        },
    );

    imgui.plotLines("FPS", context.framerate_plot_data.items, .{
        .scale_min = 0,
        .graph_size = .{ 0, 40 },
    });

    imgui.end();

    imgui.showDemoWindow();

    //var show_demo_window: bool = true;
    //imgui.c.igShowDemoWindow(&show_demo_window);
    //
    //    var showAnotherWindow: bool = true;
    //    _ = c.igBegin("imgui Another Window", &showAnotherWindow, 0);
    //    c.igText("Hello from imgui");
    //    const buttonSize: c.ImVec2 = .{
    //        .x = 0,
    //        .y = 0,
    //    };
    //    if (c.igButton("Close me", buttonSize)) {
    //        showAnotherWindow = false;
    //    }
    //    c.igEnd();

    imgui.endFrame();
}

// *********************************************************************************************
// Main
// *********************************************************************************************

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{
        //.verbose_log = true,
    }){};
    defer _ = gpa.deinit();

    var statistics_allocator = utils.StatisticsAllocator.init(gpa.allocator());

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa_allocator = statistics_allocator.allocator();
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
        defer _ = arena.reset(.retain_capacity);

        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        try update(&context, delta_time);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };

        //std.log.debug("Allocation count: {d}", .{statistics_allocator.alloc_count});
    }
}
