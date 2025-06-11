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

const MeshInstance = struct {
    name: []const u8,
    mesh: assets.MeshHandle,
    material: assets.MaterialHandle,
};

const ContextData = struct {
    camera: mini_engine.OrbitCamera,
    vertex_shader_handle: gfx.ShaderHandle,
    fragment_shader_handle: gfx.ShaderHandle,
    program_handle: gfx.ProgramHandle,
    texture_handle: gfx.TextureHandle,
    meshes: std.ArrayList(MeshInstance),

    // skybox
    cubemap_texture: gfx.TextureHandle,
    cubemap_mesh: assets.MeshHandle,
    cubemap_pipeline_handle: gfx.PipelineHandle,
    skybox_vert_shader_handle: gfx.ShaderHandle,
    skybox_frag_shader_handle: gfx.ShaderHandle,
    skybox_program_handle: gfx.ProgramHandle,
};

// *********************************************************************************************
// Helpers
// *********************************************************************************************

fn destroyMeshes(meshes: *std.ArrayList(MeshInstance)) void {
    for (meshes.items) |mesh_instance| {
        assets.destroyMesh(mesh_instance.mesh);
        assets.destroyMaterial(mesh_instance.material);
    }
    meshes.deinit();
}

// *********************************************************************************************
// Logic
// *********************************************************************************************

pub fn init(context: mini_engine.InitContext) !ContextData {
    // Shaders and program
    const vert_shader_handle = try mini_engine.loadShader(
        context.arena_allocator,
        "shader.vert.bin",
    );
    errdefer gfx.destroyShader(vert_shader_handle);

    const frag_shader_handle = try mini_engine.loadShader(
        context.arena_allocator,
        "shader.frag.bin",
    );
    errdefer gfx.destroyShader(frag_shader_handle);

    const program_handle = try gfx.createProgram(
        vert_shader_handle,
        frag_shader_handle,
        .{ .debug_name = "Simple Mesh program" },
    );
    errdefer gfx.destroyProgram(program_handle);

    // Texture
    const texture_handle = try mini_engine.loadTexture(
        context.gpa_allocator,
        "uv_texture.ktx",
    );
    errdefer gfx.destroyTexture(texture_handle);

    // Meshes
    var meshes = std.ArrayList(MeshInstance).init(context.gpa_allocator);
    errdefer destroyMeshes(&meshes);

    try meshes.append(.{
        .name = "FlightHelmet (0)",
        .mesh = try assets.loadMesh("flight-helmet.0.mesh"),
        .material = try assets.loadMaterial("FlightHelmet/material.0.mat"),
    });

    try meshes.append(.{
        .name = "FlightHelmet (1)",
        .mesh = try assets.loadMesh("flight-helmet.1.mesh"),
        .material = try assets.loadMaterial("FlightHelmet/material.1.mat"),
    });

    try meshes.append(.{
        .name = "FlightHelmet (2)",
        .mesh = try assets.loadMesh("flight-helmet.2.mesh"),
        .material = try assets.loadMaterial("FlightHelmet/material.2.mat"),
    });

    try meshes.append(.{
        .name = "FlightHelmet (3)",
        .mesh = try assets.loadMesh("flight-helmet.3.mesh"),
        .material = try assets.loadMaterial("FlightHelmet/material.3.mat"),
    });

    try meshes.append(.{
        .name = "FlightHelmet (4)",
        .mesh = try assets.loadMesh("flight-helmet.4.mesh"),
        .material = try assets.loadMaterial("FlightHelmet/material.4.mat"),
    });

    try meshes.append(.{
        .name = "FlightHelmet (5)",
        .mesh = try assets.loadMesh("flight-helmet.5.mesh"),
        .material = try assets.loadMaterial("FlightHelmet/material.5.mat"),
    });

    // Skybox

    const cubemap_texture_handle = try mini_engine.loadTexture(
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
            // .depth = .{ .enabled = true },
            .multisample = .{
                .sample_count = context.msaa_samples,
            },
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

    const camera = mini_engine.OrbitCamera.init(
        zm.f32x4(1.0, 1.0, 1.0, 1.0),
        zm.f32x4(0.0, 0.3, 0.0, 1.0),
    );

    return .{
        .camera = camera,

        .vertex_shader_handle = vert_shader_handle,
        .fragment_shader_handle = frag_shader_handle,
        .program_handle = program_handle,
        .texture_handle = texture_handle,
        .meshes = meshes,

        .cubemap_texture = cubemap_texture_handle,
        .cubemap_mesh = mesh_handle,
        .cubemap_pipeline_handle = pipeline,
        .skybox_vert_shader_handle = skybox_vert_shader_handle,
        .skybox_frag_shader_handle = skybox_frag_shader_handle,
        .skybox_program_handle = skybox_program_handle,
    };
}

pub fn deinit(context: *mini_engine.Context(ContextData)) void {
    gfx.destroyPipeline(context.data.cubemap_pipeline_handle);
    gfx.destroyTexture(context.data.cubemap_texture);
    gfx.destroyProgram(context.data.skybox_program_handle);
    gfx.destroyShader(context.data.skybox_vert_shader_handle);
    gfx.destroyShader(context.data.skybox_frag_shader_handle);
    assets.destroyMesh(context.data.cubemap_mesh);

    destroyMeshes(&context.data.meshes);

    gfx.destroyShader(context.data.vertex_shader_handle);
    gfx.destroyShader(context.data.fragment_shader_handle);
    gfx.destroyProgram(context.data.program_handle);
    gfx.destroyTexture(context.data.texture_handle);
}

pub fn update(context: *mini_engine.Context(ContextData)) !void {
    const swapchain_size = gfx.getSwapchainSize(context.framebuffer_handle);
    const aspect_ratio = @as(f32, @floatFromInt(swapchain_size[0])) / @as(f32, @floatFromInt(swapchain_size[1]));

    context.data.camera.setAspectRatio(aspect_ratio);
    context.data.camera.update();

    if (try gfx.beginRenderPass(
        context.framebuffer_handle,
        .{
            .color_attachments = &[_]gfx.Attachment{
                try context.getColorAttachment(true, .clear, .store),
            },
        },
    )) {
        defer gfx.endRenderPass();

        gfx.setViewport(.{ 0, 0 }, swapchain_size);
        gfx.setScissor(.{ 0, 0 }, swapchain_size);

        gfx.bindPipeline(context.data.cubemap_pipeline_handle);

        mini_engine.pushConstantsMvp(
            zm.identity(),
            context.data.camera.getViewMatrix(),
            context.data.camera.getProjectionMatrix(),
            .vertex,
            0,
        );

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

    if (try gfx.beginRenderPass(
        context.framebuffer_handle,
        .{
            .color_attachments = &[_]gfx.Attachment{
                try context.getColorAttachment(true, .dont_care, .store),
            },
            .depth_attachment = try context.getDepthAttachment(),
        },
    )) {
        defer gfx.endRenderPass();

        gfx.beginDebugLabel("Render geometries", gfx_types.Colors.DarkGreen);
        defer gfx.endDebugLabel();

        gfx.setViewport(.{ 0, 0 }, swapchain_size);
        gfx.setScissor(.{ 0, 0 }, swapchain_size);

        // context.bindMVP();

        for (context.data.meshes.items) |mesh_instance| {
            try context.drawMesh(
                zm.rotationY(std.math.rad_per_deg * 90.0 * context.total_time * 0.5),
                context.data.camera.getViewMatrix(),
                context.data.camera.getProjectionMatrix(),
                mesh_instance.mesh,
                mesh_instance.material,
                context.data.program_handle,
                mesh_instance.name,
            );
        }
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
        "Mesh Example",
        init,
        deinit,
        update,
        update_ui,
    );
}
