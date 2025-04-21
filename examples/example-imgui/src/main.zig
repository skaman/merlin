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

//const MeshInstance = struct {
//    name: []const u8,
//    mesh: assets.MeshHandle,
//    material: assets.MaterialHandle,
//};

const Context = struct {
    gpa_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    //vertex_shader_handle: gfx.ShaderHandle,
    //fragment_shader_handle: gfx.ShaderHandle,
    //program_handle: gfx.ProgramHandle,
    mvp_uniform_handle: gfx.UniformHandle,
    //tex_sampler_uniform_handle: gfx.UniformHandle,
    mvp_uniform_buffer_handle: gfx.BufferHandle,
    //texture_handle: gfx.TextureHandle,
    //meshes: std.ArrayList(MeshInstance),
};

// *********************************************************************************************
// Logic
// *********************************************************************************************

pub fn init(gpa_allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator) !Context {

    // Uniforms
    const mvp_uniform_handle = try gfx.registerUniformName("u_mvp");

    const max_frames_in_flight = gfx.maxFramesInFlight();
    const mvp_uniform_buffer_handle = try gfx.createBuffer(
        @sizeOf(ModelViewProj) * max_frames_in_flight,
        .{ .uniform = true },
        .host,
        .{
            .debug_name = "MVP Uniform Buffer",
        },
    );
    errdefer gfx.destroyBuffer(mvp_uniform_buffer_handle);

    return Context{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        //.vertex_shader_handle = vertex_shader_handle,
        //.fragment_shader_handle = fragment_shader_handle,
        //.program_handle = program_handle,
        .mvp_uniform_handle = mvp_uniform_handle,
        //.tex_sampler_uniform_handle = tex_sampler_uniform_handle,
        .mvp_uniform_buffer_handle = mvp_uniform_buffer_handle,
        //.texture_handle = texture_handle,
        //.meshes = try std.ArrayList(MeshInstance).init(arena_allocator),
    };
}

pub fn deinit(context: *Context) void {
    gfx.destroyBuffer(context.mvp_uniform_buffer_handle);
}

pub fn update(context: *Context, delta_time: f32) void {
    const swapchain_size = gfx.swapchainSize();
    //const aspect_ratio = @as(f32, @floatFromInt(swapchain_size[0])) / @as(f32, @floatFromInt(swapchain_size[1]));

    //gfx.setDebug(.{ .wireframe = true });

    //const mvp = ModelViewProj{
    //    .model = zm.rotationY(std.math.rad_per_deg * 90.0 * delta_time),
    //    .view = zm.lookAtLh(
    //        zm.f32x4(1.0, 1.0, 1.0, 1.0),
    //        zm.f32x4(0.0, 0.3, 0.0, 1.0),
    //        zm.f32x4(0.0, -1.0, 0.0, 0.0),
    //    ),
    //    .proj = zm.orthographicLh(
    //        @floatFromInt(swapchain_size[0]),
    //        @floatFromInt(swapchain_size[1]),
    //        0,
    //        1000,
    //    ),
    //};
    //const mvp_ptr: [*]const u8 = @ptrCast(&mvp);
    //const current_frame_in_flight = gfx.currentFrameInFlight();
    //const mvp_offset = current_frame_in_flight * @sizeOf(ModelViewProj);
    //gfx.updateBufferFromMemory(
    //    context.mvp_uniform_buffer_handle,
    //    mvp_ptr[0..@sizeOf(ModelViewProj)],
    //    mvp_offset,
    //) catch |err| {
    //    std.log.err("Failed to update MVP uniform buffer: {}", .{err});
    //};

    //gfx.beginDebugLabel("Render geometries", gfx_types.Colors.DarkGreen);
    //defer gfx.endDebugLabel();

    gfx.setViewport(.{ 0, 0 }, swapchain_size);
    gfx.setScissor(.{ 0, 0 }, swapchain_size);

    //gfx.bindProgram(context.program_handle);
    //gfx.bindUniformBuffer(
    //    context.mvp_uniform_handle,
    //    context.mvp_uniform_buffer_handle,
    //    mvp_offset,
    //);

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

    try imgui.init(.{
        .window_handle = window_handle,
    });
    defer imgui.deinit();

    var context = try init(gpa_allocator, arena_allocator);
    defer deinit(&context);

    const start_time = std.time.microTimestamp();
    var last_current_time = start_time;

    //var fps_counter: u32 = 0;
    //var fps_timer: f32 = 0.0;

    while (!platform.shouldCloseWindow(window_handle)) {
        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        //fps_counter += 1;
        //fps_timer += delta_time;
        //if (fps_timer >= 1.0) {
        //    std.debug.print("FPS: {d}\n", .{fps_counter});
        //    fps_counter = 0;
        //    fps_timer -= 1.0;
        //}

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        gfx.beginDebugLabel("Frame", gfx_types.Colors.Red);
        defer gfx.endDebugLabel();

        //const time = @as(f32, @floatFromInt(current_time - start_time)) / 1_000_000.0;

        update(&context, delta_time);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };

        _ = arena.reset(.retain_capacity);
    }
}
