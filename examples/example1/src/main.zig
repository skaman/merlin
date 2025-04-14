const std = @import("std");

const assets = @import("merlin_assets");
const gfx = @import("merlin_gfx");
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

const MeshInstance = struct {
    name: []const u8,
    mesh: assets.MeshHandle,
    material: assets.MaterialHandle,
};

const Context = struct {
    gpa_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    vertex_shader_handle: gfx.ShaderHandle,
    fragment_shader_handle: gfx.ShaderHandle,
    program_handle: gfx.ProgramHandle,
    mvp_uniform_handle: gfx.UniformHandle,
    tex_sampler_uniform_handle: gfx.UniformHandle,
    mvp_uniform_buffer_handle: gfx.BufferHandle,
    texture_handle: gfx.TextureHandle,
    meshes: std.ArrayList(MeshInstance),
};

// *********************************************************************************************
// Helpers
// *********************************************************************************************

fn getAssetPath(allocator: std.mem.Allocator, asset_name: []const u8) ![]const u8 {
    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_path);

    return try std.fs.path.join(allocator, &[_][]const u8{
        exe_path,
        std.mem.bytesAsSlice(u8, "assets"),
        asset_name,
    });
}

fn loadShader(allocator: std.mem.Allocator, filename: []const u8) !gfx.ShaderHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try gfx.createShader(file.reader().any(), .{
        .debug_name = filename,
    });
}

fn loadTexture(allocator: std.mem.Allocator, filename: []const u8) !gfx.TextureHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();

    return try gfx.createTextureFromKTX(
        file.reader().any(),
        @intCast(stat.size),
        .{
            .debug_name = filename,
        },
    );
}

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

pub fn init(gpa_allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator) !Context {

    // Shaders and program
    const vert_shader_handle = try loadShader(
        arena_allocator,
        "shader.vert.bin",
    );
    errdefer gfx.destroyShader(vert_shader_handle);

    const frag_shader_handle = try loadShader(
        arena_allocator,
        "shader.frag.bin",
    );
    errdefer gfx.destroyShader(frag_shader_handle);

    const program_handle = try gfx.createProgram(
        vert_shader_handle,
        frag_shader_handle,
    );
    errdefer gfx.destroyProgram(program_handle);

    // Uniforms
    const mvp_uniform_handle = try gfx.registerUniformName("u_mvp");
    const tex_sampler_uniform_handle = try gfx.registerUniformName("u_tex_sampler");

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

    // Texture
    const texture_handle = try loadTexture(
        gpa_allocator,
        "uv_texture.ktx",
    );
    errdefer gfx.destroyTexture(texture_handle);

    // Meshes
    var meshes = std.ArrayList(MeshInstance).init(gpa_allocator);
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

    return Context{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .vertex_shader_handle = vert_shader_handle,
        .fragment_shader_handle = frag_shader_handle,
        .program_handle = program_handle,
        .mvp_uniform_handle = mvp_uniform_handle,
        .tex_sampler_uniform_handle = tex_sampler_uniform_handle,
        .mvp_uniform_buffer_handle = mvp_uniform_buffer_handle,
        .texture_handle = texture_handle,
        .meshes = meshes,
    };
}

pub fn deinit(context: *Context) void {
    destroyMeshes(&context.meshes);

    gfx.destroyShader(context.vertex_shader_handle);
    gfx.destroyShader(context.fragment_shader_handle);
    gfx.destroyProgram(context.program_handle);
    gfx.destroyBuffer(context.mvp_uniform_buffer_handle);
    gfx.destroyTexture(context.texture_handle);
}

pub fn update(context: *Context, time: f32) void {
    const swapchain_size = gfx.swapchainSize();
    const aspect_ratio = @as(f32, @floatFromInt(swapchain_size[0])) / @as(f32, @floatFromInt(swapchain_size[1]));

    const mvp = ModelViewProj{
        .model = zm.rotationY(std.math.rad_per_deg * 90.0 * time),
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
    const current_frame_in_flight = gfx.currentFrameInFlight();
    const mvp_offset = current_frame_in_flight * @sizeOf(ModelViewProj);
    gfx.updateBufferFromMemory(
        context.mvp_uniform_buffer_handle,
        mvp_ptr[0..@sizeOf(ModelViewProj)],
        mvp_offset,
    ) catch |err| {
        std.log.err("Failed to update MVP uniform buffer: {}", .{err});
    };

    gfx.beginDebugLabel("Render geometries", gfx_types.Colors.DarkGreen);
    defer gfx.endDebugLabel();

    gfx.setViewport(.{ 0, 0 }, swapchain_size);
    gfx.setScissor(.{ 0, 0 }, swapchain_size);

    gfx.bindProgram(context.program_handle);
    gfx.bindUniformBuffer(
        context.mvp_uniform_handle,
        context.mvp_uniform_buffer_handle,
        mvp_offset,
    );

    for (context.meshes.items) |mesh_instance| {
        const mesh = assets.mesh(mesh_instance.mesh);
        const material = assets.material(mesh_instance.material);

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
                    context.tex_sampler_uniform_handle,
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

        gfx.bindPipelineLayout(mesh.pipeline_handle);
        gfx.bindVertexBuffer(mesh.buffer_handle, mesh.vertex_buffer_offset);
        gfx.bindIndexBuffer(mesh.buffer_handle, mesh.index_buffer_offset);
        gfx.drawIndexed(
            mesh.indices_count,
            1,
            0,
            0,
            0,
            mesh.index_type,
        );
    }
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
        .{
            .type = .glfw,
            .window = .{
                .width = 800,
                .height = 600,
                .title = "Example 1",
            },
        },
    );
    defer platform.deinit();

    try gfx.init(
        gpa_allocator,
        .{
            .renderer_type = .vulkan,
            .enable_vulkan_debug = true,
        },
    );
    defer gfx.deinit();

    try assets.init(gpa_allocator);
    defer assets.deinit();

    var context = try init(gpa_allocator, arena_allocator);
    defer deinit(&context);

    const start_time = std.time.microTimestamp();
    var last_current_time = start_time;

    var fps_counter: u32 = 0;
    var fps_timer: f32 = 0.0;

    while (!platform.shouldCloseDefaultWindow()) {
        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        fps_counter += 1;
        fps_timer += delta_time;
        if (fps_timer >= 1.0) {
            std.debug.print("FPS: {d}\n", .{fps_counter});
            fps_counter = 0;
            fps_timer -= 1.0;
        }

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        gfx.beginDebugLabel("Frame", gfx_types.Colors.Red);
        defer gfx.endDebugLabel();

        const time = @as(f32, @floatFromInt(current_time - start_time)) / 1_000_000.0;

        update(&context, time);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };

        _ = arena.reset(.retain_capacity);
    }
}
