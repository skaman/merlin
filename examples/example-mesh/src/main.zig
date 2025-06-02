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

const ModelViewProj = struct {
    model: zm.Mat align(16),
    view: zm.Mat align(16),
    proj: zm.Mat align(16),
};

const MeshInstance = struct {
    name: []const u8,
    mesh: assets.MeshHandle,
    material: assets.MaterialHandle,
};

const DepthImage = struct {
    handle: gfx.ImageHandle,
    view_handle: gfx.ImageViewHandle,
    size: [2]u32,
    format: gfx.ImageFormat,
};

const ContextData = struct {
    depth_image: ?DepthImage,
    vertex_shader_handle: gfx.ShaderHandle,
    fragment_shader_handle: gfx.ShaderHandle,
    program_handle: gfx.ProgramHandle,
    mvp_uniform_handle: gfx.NameHandle,
    tex_sampler_uniform_handle: gfx.NameHandle,
    mvp_uniform_buffer_handle: gfx.BufferHandle,
    texture_handle: gfx.TextureHandle,
    meshes: std.ArrayList(MeshInstance),
    pipelines: std.AutoHashMap(gfx.PipelineLayoutHandle, gfx.PipelineHandle),
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

fn getPipeline(
    data: *ContextData,
    pipeline_layout: gfx.PipelineLayoutHandle,
) !gfx.PipelineHandle {
    if (data.pipelines.get(pipeline_layout)) |pipeline| {
        return pipeline;
    }

    const pipeline = try gfx.createPipeline(.{
        .program_handle = data.program_handle,
        .pipeline_layout_handle = pipeline_layout,
        .render_options = .{
            .cull_mode = .back,
            .front_face = .counter_clockwise,
            .depth = .{ .enabled = true },
        },
        .color_attachment_formats = &[_]gfx.ImageFormat{
            gfx.getSurfaceColorFormat(),
        },
        .depth_attachment_format = gfx.getSurfaceDepthFormat(),
        .debug_options = .{
            .debug_name = "Simple Mesh Pipeline",
        },
    });
    errdefer gfx.destroyPipeline(pipeline);

    try data.pipelines.put(pipeline_layout, pipeline);

    return pipeline;
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

    // Uniforms
    const mvp_uniform_handle = gfx.nameHandle("u_mvp");
    const tex_sampler_uniform_handle = gfx.nameHandle("u_tex_sampler");

    const max_frames_in_flight = gfx.getMaxFramesInFlight();
    const mvp_uniform_buffer_handle = try gfx.createBuffer(
        @sizeOf(ModelViewProj) * max_frames_in_flight,
        .{ .uniform = true },
        .host,
        .{
            .debug_name = "MVP Uniform Buffer",
        },
    );
    errdefer gfx.destroyBuffer(mvp_uniform_buffer_handle);

    // Texture
    const texture_handle = try mini_engine.loadTexture(
        context.gpa_allocator,
        "uv_texture.ktx",
    );
    errdefer gfx.destroyTexture(texture_handle);

    // Meshes
    var meshes = std.ArrayList(MeshInstance).init(context.gpa_allocator);
    errdefer destroyMeshes(&meshes);

    //try meshes.append(try assets.loadMesh("flight-helmet.0.mesh"));
    //try meshes.append(try assets.loadMesh("flight-helmet.1.mesh"));
    //try meshes.append(try assets.loadMesh("flight-helmet.2.mesh"));
    //try meshes.append(try assets.loadMesh("flight-helmet.3.mesh"));
    //try meshes.append(try assets.loadMesh("flight-helmet.4.mesh"));
    //try meshes.append(try assets.loadMesh("flight-helmet.5.mesh"));

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

    //try meshes.append(.{
    //    .name = "BoxTextured",
    //    .mesh = try assets.loadMesh("box-textured.0.mesh"),
    //    .material = try assets.loadMaterial("BoxTextured/material.0.mat"),
    //});

    return .{
        .depth_image = null,
        .vertex_shader_handle = vert_shader_handle,
        .fragment_shader_handle = frag_shader_handle,
        .program_handle = program_handle,
        .mvp_uniform_handle = mvp_uniform_handle,
        .tex_sampler_uniform_handle = tex_sampler_uniform_handle,
        .mvp_uniform_buffer_handle = mvp_uniform_buffer_handle,
        .texture_handle = texture_handle,
        .meshes = meshes,
        .pipelines = .init(context.gpa_allocator),
    };
}

pub fn deinit(context: *mini_engine.Context(ContextData)) void {
    destroyMeshes(&context.data.meshes);

    gfx.destroyShader(context.data.vertex_shader_handle);
    gfx.destroyShader(context.data.fragment_shader_handle);
    gfx.destroyProgram(context.data.program_handle);
    gfx.destroyBuffer(context.data.mvp_uniform_buffer_handle);
    gfx.destroyTexture(context.data.texture_handle);

    if (context.data.depth_image) |depth_image| {
        gfx.destroyImage(depth_image.handle);
        gfx.destroyImageView(depth_image.view_handle);
    }
    var it = context.data.pipelines.iterator();
    while (it.next()) |entry| {
        gfx.destroyPipeline(entry.value_ptr.*);
    }

    context.data.pipelines.deinit();
}

pub fn update(context: *mini_engine.Context(ContextData)) !void {
    const swapchain_size = gfx.getSwapchainSize(context.framebuffer_handle);
    const aspect_ratio = @as(f32, @floatFromInt(swapchain_size[0])) / @as(f32, @floatFromInt(swapchain_size[1]));

    const mvp = ModelViewProj{
        .model = zm.rotationY(std.math.rad_per_deg * 90.0 * context.total_time),
        .view = zm.lookAtLh(
            zm.f32x4(1.0, 1.0, 1.0, 1.0),
            zm.f32x4(0.0, 0.3, 0.0, 1.0),
            zm.f32x4(0.0, -1.0, 0.0, 0.0),
        ),
        .proj = zm.perspectiveFovLh(
            std.math.rad_per_deg * 45.0,
            aspect_ratio,
            0.1,
            20.0,
        ),
    };
    const mvp_ptr: [*]const u8 = @ptrCast(&mvp);
    const current_frame_in_flight = gfx.getCurrentFrameInFlight();
    const mvp_offset = current_frame_in_flight * @sizeOf(ModelViewProj);
    try gfx.updateBufferFromMemory(
        context.data.mvp_uniform_buffer_handle,
        mvp_ptr[0..@sizeOf(ModelViewProj)],
        mvp_offset,
    );

    if (context.data.depth_image == null or
        context.data.depth_image.?.size[0] != swapchain_size[0] or
        context.data.depth_image.?.size[1] != swapchain_size[1])
    {
        if (context.data.depth_image) |old_depth_image| {
            gfx.destroyImage(old_depth_image.handle);
            gfx.destroyImageView(old_depth_image.view_handle);
        }

        const depth_format = gfx.getSurfaceDepthFormat();
        const depth_image_handle = try gfx.createImage(.{
            .format = depth_format,
            .width = swapchain_size[0],
            .height = swapchain_size[1],
            .usage = .{
                .depth_stencil_attachment = true,
            },
        });
        errdefer gfx.destroyImage(depth_image_handle);

        const depth_image_view_handle = try gfx.createImageView(
            depth_image_handle,
            .{
                .format = depth_format,
                .aspect = .{
                    .depth = true,
                },
            },
        );
        errdefer gfx.destroyImageView(depth_image_view_handle);

        context.data.depth_image = .{
            .handle = depth_image_handle,
            .view_handle = depth_image_view_handle,
            .size = swapchain_size,
            .format = depth_format,
        };
    }

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
        .depth_attachment = .{
            .image = context.data.depth_image.?.handle,
            .image_view = context.data.depth_image.?.view_handle,
            .format = context.data.depth_image.?.format,
            .load_op = .clear,
            .store_op = .dont_care,
        },
    };

    if (try gfx.beginRenderPass(
        context.framebuffer_handle,
        main_render_pass_options,
    )) {
        defer gfx.endRenderPass();

        gfx.beginDebugLabel("Render geometries", gfx_types.Colors.DarkGreen);
        defer gfx.endDebugLabel();

        gfx.setViewport(.{ 0, 0 }, swapchain_size);
        gfx.setScissor(.{ 0, 0 }, swapchain_size);

        // gfx.bindProgram(context.data.program_handle);
        gfx.bindUniformBuffer(
            context.data.mvp_uniform_handle,
            context.data.mvp_uniform_buffer_handle,
            mvp_offset,
        );

        for (context.data.meshes.items) |mesh_instance| {
            const mesh = assets.mesh(mesh_instance.mesh);
            const material = assets.material(mesh_instance.material);

            const pipeline_handle = try getPipeline(
                &context.data,
                mesh.pipeline_handle,
            );

            gfx.bindPipeline(pipeline_handle);

            gfx.insertDebugLabel(
                mesh_instance.name,
                gfx_types.Colors.LightGray,
            );

            gfx.bindUniformBuffer(
                assets.materialUniformHandle(),
                assets.materialUniformBufferHandle(),
                assets.materialUniformBufferOffset(mesh_instance.material),
            );

            switch (material.pbr) {
                .pbr_metallic_roughness => |pbr| {
                    gfx.bindCombinedSampler(
                        context.data.tex_sampler_uniform_handle,
                        pbr.base_color_texture_handle,
                    );
                },
                .pbr_specular_glossiness => |pbr| {
                    _ = pbr;
                    //gfx.bindCombinedSampler(
                    //    context.tex_sampler_uniform_handle,
                    //    pbr.diffuse_texture_handle,
                    //);
                },
            }

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

    const ui_render_pass_options = gfx.RenderPassOptions{
        .color_attachments = &[_]gfx.Attachment{
            .{
                .image = gfx.getSurfaceImage(context.framebuffer_handle),
                .image_view = gfx.getSurfaceImageView(context.framebuffer_handle),
                .format = gfx.getSurfaceColorFormat(),
                .load_op = .dont_care,
                .store_op = .store,
            },
        },
        .depth_attachment = null,
    };
    if (try gfx.beginRenderPass(
        context.framebuffer_handle,
        ui_render_pass_options,
    )) {
        defer gfx.endRenderPass();
        imgui.beginFrame(context.delta_time);

        var show_demo_window: bool = true;
        imgui.c.igShowDemoWindow(&show_demo_window);

        imgui.endFrame();
    }
}

// *********************************************************************************************
// Main
// *********************************************************************************************

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = mini_engine.customLog,
};

pub fn main() !void {
    try mini_engine.run_engine(
        ContextData,
        "Mesh Example",
        init,
        deinit,
        update,
    );
}
