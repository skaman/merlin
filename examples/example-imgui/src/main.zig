const std = @import("std");

const mini_engine = @import("mini_engine");
const platform = mini_engine.platform;
const utils = mini_engine.utils;
const gfx_types = utils.gfx_types;
const zm = mini_engine.zmath;
const assets = mini_engine.assets;
const gfx = mini_engine.gfx;
const imgui = mini_engine.imgui;

// *********************************************************************************************
// Structs
// *********************************************************************************************

const ContextData = struct {
    framerate_plot_data: std.ArrayList(f32),
};

// *********************************************************************************************
// Logic
// *********************************************************************************************

pub fn init(context: mini_engine.InitContext) !ContextData {
    return .{
        .framerate_plot_data = .init(context.gpa_allocator),
    };
}

pub fn deinit(context: *mini_engine.Context(ContextData)) void {
    context.data.framerate_plot_data.deinit();
}

pub fn update(context: *mini_engine.Context(ContextData)) !void {
    {
        if (!try gfx.beginRenderPass(
            context.framebuffer_handle,
            context.main_render_pass_handle,
        )) return;
        defer gfx.endRenderPass();
    }

    imgui.beginFrame(context.delta_time);
    defer imgui.endFrame();

    _ = imgui.c.igBegin("Statistics", null, imgui.c.ImGuiWindowFlags_None);

    const io = imgui.c.igGetIO_Nil();
    try context.data.framerate_plot_data.append(io.*.Framerate);
    if (context.data.framerate_plot_data.items.len > 2000) {
        _ = context.data.framerate_plot_data.orderedRemove(0);
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
        context.data.framerate_plot_data.items.ptr,
        @intCast(context.data.framerate_plot_data.items.len),
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
}

// *********************************************************************************************
// Main
// *********************************************************************************************

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = mini_engine.customLog,
};

pub fn main() !void {
    try mini_engine.run_engine(
        ContextData,
        "ImGUI Example",
        init,
        deinit,
        update,
    );
}
