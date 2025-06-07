const std = @import("std");

const mini_engine = @import("mini_engine");
const gfx = mini_engine.gfx;
const imgui = mini_engine.imgui;
const assets = mini_engine.assets;
const zm = mini_engine.zmath;

// *********************************************************************************************
// Structs
// *********************************************************************************************

const ContextData = struct {
    cubemap_texture: gfx.TextureHandle,
    cubemap_mesh: assets.MeshHandle,
    skybox_vert_shader_handle: gfx.ShaderHandle,
    skybox_frag_shader_handle: gfx.ShaderHandle,
    skybox_program_handle: gfx.ProgramHandle,
    cubemap_pipeline_handle: gfx.PipelineHandle,
};

// *********************************************************************************************
// Logic
// *********************************************************************************************

pub fn init(context: mini_engine.InitContext) !ContextData {
    const texture_handle = try mini_engine.loadTexture(
        context.gpa_allocator,
        "cubemap.ktx",
    );
    errdefer gfx.destroyTexture(texture_handle);

    const mesh_handle = try assets.loadMesh("cube.mesh");
    errdefer assets.destroyMesh(mesh_handle);

    const skybox_vert_shader_handle = try mini_engine.loadShader(
        context.arena_allocator,
        "skybox.vert.bin",
    );
    errdefer gfx.destroyShader(skybox_vert_shader_handle);

    const skybox_frag_shader_handle = try mini_engine.loadShader(
        context.arena_allocator,
        "skybox.frag.bin",
    );
    errdefer gfx.destroyShader(skybox_frag_shader_handle);

    const skybox_program_handle = try gfx.createProgram(
        skybox_vert_shader_handle,
        skybox_frag_shader_handle,
        .{ .debug_name = "Skybox program" },
    );
    errdefer gfx.destroyProgram(skybox_program_handle);

    const mesh = assets.mesh(mesh_handle);

    const pipeline = try gfx.createPipeline(.{
        .program_handle = skybox_program_handle,
        .pipeline_layout_handle = mesh.pipeline_handle,
        .render_options = .{
            .cull_mode = .front,
            .front_face = .counter_clockwise,
            .depth = .{ .enabled = true },
        },
        .color_attachment_formats = &[_]gfx.ImageFormat{
            gfx.getSurfaceColorFormat(),
        },
        .depth_attachment_format = gfx.getSurfaceDepthFormat(),
        .debug_options = .{
            .debug_name = "Skybox Pipeline",
        },
    });
    errdefer gfx.destroyPipeline(pipeline);

    return .{
        .cubemap_texture = texture_handle,
        .cubemap_mesh = mesh_handle,
        .skybox_vert_shader_handle = skybox_vert_shader_handle,
        .skybox_frag_shader_handle = skybox_frag_shader_handle,
        .skybox_program_handle = skybox_program_handle,
        .cubemap_pipeline_handle = pipeline,
    };
}

pub fn deinit(context: *mini_engine.Context(ContextData)) void {
    gfx.destroyPipeline(context.data.cubemap_pipeline_handle);
    gfx.destroyTexture(context.data.cubemap_texture);
    gfx.destroyProgram(context.data.skybox_program_handle);
    gfx.destroyShader(context.data.skybox_vert_shader_handle);
    gfx.destroyShader(context.data.skybox_frag_shader_handle);
    assets.destroyMesh(context.data.cubemap_mesh);
}

pub fn update(context: *mini_engine.Context(ContextData)) !void {
    const swapchain_size = gfx.getSwapchainSize(context.framebuffer_handle);
    const aspect_ratio = @as(f32, @floatFromInt(swapchain_size[0])) / @as(f32, @floatFromInt(swapchain_size[1]));

    try context.setMVP(
        zm.rotationY(std.math.rad_per_deg * 90.0 * context.total_time * 0.5),
        zm.lookAtLh(
            zm.f32x4(1.0, 1.0, 1.0, 1.0),
            zm.f32x4(0.0, 0.3, 0.0, 1.0),
            zm.f32x4(0.0, -1.0, 0.0, 0.0),
        ),
        zm.perspectiveFovLh(
            std.math.rad_per_deg * 45.0,
            aspect_ratio,
            0.1,
            20.0,
        ),
    );

    const main_render_pass_options = gfx.RenderPassOptions{
        .color_attachments = &[_]gfx.Attachment{
            .{
                .image = gfx.getSurfaceImage(context.framebuffer_handle),
                .image_view = gfx.getSurfaceImageView(context.framebuffer_handle),
                .format = gfx.getSurfaceColorFormat(),
                .load_op = .clear,
                .store_op = .store,
            },
        },
    };
    if (try gfx.beginRenderPass(
        context.framebuffer_handle,
        main_render_pass_options,
    )) {
        defer gfx.endRenderPass();

        gfx.setViewport(.{ 0, 0 }, swapchain_size);
        gfx.setScissor(.{ 0, 0 }, swapchain_size);

        context.bindMVP();

        gfx.bindPipeline(context.data.cubemap_pipeline_handle);

        gfx.bindCombinedSampler(
            context.tex_sampler_uniform_handle,
            context.data.cubemap_texture,
        );

        const mesh = assets.mesh(context.data.cubemap_mesh);
        gfx.bindVertexBuffer(mesh.buffer_handle, mesh.vertex_buffer_offset);
        gfx.bindIndexBuffer(
            mesh.buffer_handle,
            mesh.index_buffer_offset,
            mesh.index_type,
        );
        gfx.drawIndexed(
            mesh.indices_count,
            1,
            0,
            0,
            0,
        );
    }
}

fn update_ui(_: *mini_engine.Context(ContextData)) !void {
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
        "Cubemap Example",
        init,
        deinit,
        update,
        update_ui,
    );
}
