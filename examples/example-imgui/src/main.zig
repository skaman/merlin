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

    _ = imgui.c.igBegin("Statistics", null, imgui.c.ImGuiWindowFlags_None);

    const io = imgui.c.igGetIO_Nil();
    try context.framerate_plot_data.append(io.*.Framerate);
    if (context.framerate_plot_data.items.len > 2000) {
        _ = context.framerate_plot_data.orderedRemove(0);
    }

    const text = try std.fmt.allocPrintZ(
        context.arena_allocator,
        "{d:.3} ms/frame ({d:.1} FPS)",
        .{
            1000.0 / io.*.Framerate,
            io.*.Framerate,
        },
    );

    imgui.c.igPlotLines_FloatPtr(
        text.ptr,
        context.framerate_plot_data.items.ptr,
        @intCast(context.framerate_plot_data.items.len),
        0,
        null,
        0.0,
        std.math.floatMax(f32),
        .{ .x = 0, .y = 0 },
        0,
    );

    imgui.c.igEnd();

    var show_demo_window: bool = true;
    imgui.c.igShowDemoWindow(&show_demo_window);

    imgui.endFrame();
}

// *********************************************************************************************
// Main
// *********************************************************************************************

const AnsiColorRed = "\x1b[31m";
const AnsiColorYellow = "\x1b[33m";
const AnsiColorWhite = "\x1b[37m";
const AnsiColorGray = "\x1b[90m";
const AnsiColorLightGray = "\x1b[37;1m";
const AnsiColorReset = "\x1b[0m";

pub fn customLog(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    const color = comptime switch (level) {
        .info => AnsiColorWhite,
        .warn => AnsiColorYellow,
        .err => AnsiColorRed,
        .debug => AnsiColorGray,
    };

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(
            color ++ level_txt ++ prefix2 ++ format ++ AnsiColorReset ++ "\n",
            args,
        ) catch return;
        bw.flush() catch return;
    }
}

pub const std_options: std.Options = .{
    .logFn = customLog,
};

pub fn main() !void {
    //std.options.logFn = customLog;

    var gpa = std.heap.GeneralPurposeAllocator(.{
        //.verbose_log = true,
    }){};
    defer _ = gpa.deinit();

    var statistics_allocator = utils.StatisticsAllocator.init(gpa.allocator());
    //defer statistics_allocator.deinit();

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

    const render_pass_handle = try gfx.createRenderPass();
    defer gfx.destroyRenderPass(render_pass_handle);

    const framebuffer_handle = try gfx.createFramebuffer(
        window_handle,
        render_pass_handle,
    );
    defer gfx.destroyFramebuffer(framebuffer_handle);

    try assets.init(gpa_allocator);
    defer assets.deinit();

    try imgui.init(
        gpa_allocator,
        render_pass_handle,
        framebuffer_handle,
        .{
            .window_handle = window_handle,
        },
    );
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
            @panic("Failed to end frame");
        };

        //const alloc_count = @atomicLoad(usize, &statistics_allocator.alloc_count, .unordered);
        //const alloc_size = @atomicLoad(usize, &statistics_allocator.alloc_size, .unordered);
        //std.log.debug("Allocation count: {d}", .{alloc_count});
        //std.log.debug("Allocation memory: {d}", .{alloc_size});
    }
}
