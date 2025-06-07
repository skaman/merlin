const std = @import("std");

pub const assets = @import("merlin_assets");
pub const gfx = @import("merlin_gfx");
pub const imgui = @import("merlin_imgui");
pub const platform = @import("merlin_platform");
pub const utils = @import("merlin_utils");
pub const zmath = @import("zmath");

pub const InitContext = struct {
    gpa_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    window_handle: platform.WindowHandle,
    framebuffer_handle: gfx.FramebufferHandle,
};

const ModelViewProj = struct {
    model: zmath.Mat align(16),
    view: zmath.Mat align(16),
    proj: zmath.Mat align(16),
};

const DepthImage = struct {
    handle: gfx.ImageHandle,
    view_handle: gfx.ImageViewHandle,

    pub fn deinit(self: *const DepthImage) void {
        gfx.destroyImageView(self.view_handle);
        gfx.destroyImage(self.handle);
    }
};

const PipelineKey = packed struct {
    pipeline_layout: gfx.PipelineLayoutHandle,
    program_handle: gfx.ProgramHandle,
};

pub fn Context(comptime T: type) type {
    return struct {
        gpa_allocator: std.mem.Allocator,
        arena_allocator: std.mem.Allocator,
        window_handle: platform.WindowHandle,
        framebuffer_handle: gfx.FramebufferHandle,
        mvp_uniform_handle: gfx.NameHandle,
        mvp_uniform_buffer_handle: gfx.BufferHandle,
        tex_sampler_uniform_handle: gfx.NameHandle,
        depth_images: std.ArrayList(DepthImage),
        depth_image_size: [2]u32,
        depth_image_format: gfx.ImageFormat,
        pipelines: std.AutoHashMap(PipelineKey, gfx.PipelineHandle),
        delta_time: f32,
        total_time: f32,
        data: T,

        pub fn setMVP(
            self: *Context(T),
            model: zmath.Mat,
            view: zmath.Mat,
            proj: zmath.Mat,
        ) !void {
            const mvp = ModelViewProj{
                .model = model,
                .view = view,
                .proj = proj,
            };
            const mvp_ptr: [*]const u8 = @ptrCast(&mvp);
            const current_frame_in_flight = gfx.getCurrentFrameInFlight();
            const mvp_offset = current_frame_in_flight * @sizeOf(ModelViewProj);
            try gfx.updateBufferFromMemory(
                self.mvp_uniform_buffer_handle,
                mvp_ptr[0..@sizeOf(ModelViewProj)],
                mvp_offset,
            );
        }

        pub fn bindMVP(self: *Context(T)) void {
            const current_frame_in_flight = gfx.getCurrentFrameInFlight();
            const mvp_offset = current_frame_in_flight * @sizeOf(ModelViewProj);
            gfx.bindUniformBuffer(
                self.mvp_uniform_handle,
                self.mvp_uniform_buffer_handle,
                mvp_offset,
            );
        }

        pub fn getDepthImage(self: *Context(T)) !DepthImage {
            const swapchain_size = gfx.getSwapchainSize(self.framebuffer_handle);
            if (self.depth_images.items.len == 0 or
                self.depth_image_size[0] != swapchain_size[0] or
                self.depth_image_size[1] != swapchain_size[1])
            {
                for (self.depth_images.items) |depth_image| {
                    depth_image.deinit();
                }
                self.depth_images.clearRetainingCapacity();

                const max_frames_in_flight = gfx.getMaxFramesInFlight();
                const depth_format = gfx.getSurfaceDepthFormat();
                for (0..max_frames_in_flight) |_| {
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

                    try self.depth_images.append(.{
                        .handle = depth_image_handle,
                        .view_handle = depth_image_view_handle,
                    });
                }

                self.depth_image_format = depth_format;
                self.depth_image_size = swapchain_size;
            }

            const current_frame_in_flight = gfx.getCurrentFrameInFlight();
            return self.depth_images.items[current_frame_in_flight];
        }

        fn getPipeline(
            self: *Context(T),
            pipeline_layout: gfx.PipelineLayoutHandle,
            program_handle: gfx.ProgramHandle,
        ) !gfx.PipelineHandle {
            if (self.pipelines.get(.{
                .pipeline_layout = pipeline_layout,
                .program_handle = program_handle,
            })) |pipeline| {
                return pipeline;
            }

            const pipeline = try gfx.createPipeline(.{
                .program_handle = program_handle,
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

            try self.pipelines.put(
                .{
                    .pipeline_layout = pipeline_layout,
                    .program_handle = program_handle,
                },
                pipeline,
            );

            return pipeline;
        }

        pub fn drawMesh(
            self: *Context(T),
            mesh_handle: assets.MeshHandle,
            material_handle: assets.MaterialHandle,
            program: gfx.ProgramHandle,
            debug_label: []const u8,
        ) !void {
            const mesh = assets.mesh(mesh_handle);
            const material = assets.material(material_handle);

            const pipeline_handle = try self.getPipeline(
                mesh.pipeline_handle,
                program,
            );

            gfx.bindPipeline(pipeline_handle);

            gfx.insertDebugLabel(
                debug_label,
                utils.gfx_types.Colors.LightGray,
            );

            gfx.bindUniformBuffer(
                assets.materialUniformHandle(),
                assets.materialUniformBufferHandle(),
                assets.materialUniformBufferOffset(material_handle),
            );

            switch (material.pbr) {
                .pbr_metallic_roughness => |pbr| {
                    gfx.bindCombinedSampler(
                        self.tex_sampler_uniform_handle,
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
    };
}

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

fn getAssetPath(allocator: std.mem.Allocator, asset_name: []const u8) ![]const u8 {
    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_path);

    return try std.fs.path.join(allocator, &[_][]const u8{
        exe_path,
        std.mem.bytesAsSlice(u8, "assets"),
        asset_name,
    });
}

pub fn loadShader(allocator: std.mem.Allocator, filename: []const u8) !gfx.ShaderHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try gfx.createShader(file.reader().any(), .{
        .debug_name = filename,
    });
}

pub fn loadTexture(allocator: std.mem.Allocator, filename: []const u8) !gfx.TextureHandle {
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

pub fn run_engine(
    comptime T: type,
    name: []const u8,
    init_callback: fn (InitContext) anyerror!T,
    deinit_callback: fn (*Context(T)) void,
    update_callback: fn (*Context(T)) anyerror!void,
    update_ui_callback: fn (*Context(T)) anyerror!void,
) !void {
    // Allocators
    var gpa = std.heap.GeneralPurposeAllocator(.{
        //.verbose_log = true,
    }){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa_allocator = gpa.allocator();
    const arena_allocator = arena.allocator();

    // Platform
    try platform.init(
        gpa_allocator,
        .{ .type = .glfw },
    );
    defer platform.deinit();

    // Window
    const window_handle = try platform.createWindow(.{
        .width = 1280,
        .height = 720,
        .title = name,
    });
    defer platform.destroyWindow(window_handle);

    // Graphics
    try gfx.init(
        gpa_allocator,
        .{
            .renderer_type = .vulkan,
            .window_handle = window_handle,
            .enable_vulkan_debug = true,
        },
    );
    defer gfx.deinit();

    // Framebuffer
    const framebuffer_handle = try gfx.createFramebuffer(
        window_handle,
        // main_render_pass_handle,
    );
    defer gfx.destroyFramebuffer(framebuffer_handle);

    // Assets system
    try assets.init(gpa_allocator);
    defer assets.deinit();

    // ImGUI
    try imgui.init(
        gpa_allocator,
        framebuffer_handle,
        .{
            .window_handle = window_handle,
        },
    );
    defer imgui.deinit();

    const data = try init_callback(.{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .window_handle = window_handle,
        .framebuffer_handle = framebuffer_handle,
    });

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
    defer gfx.destroyBuffer(mvp_uniform_buffer_handle);

    var context = Context(T){
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .window_handle = window_handle,
        .framebuffer_handle = framebuffer_handle,
        .mvp_uniform_handle = mvp_uniform_handle,
        .mvp_uniform_buffer_handle = mvp_uniform_buffer_handle,
        .tex_sampler_uniform_handle = tex_sampler_uniform_handle,
        .depth_images = .init(gpa_allocator),
        .depth_image_size = [_]u32{ 0, 0 },
        .depth_image_format = undefined,
        .pipelines = .init(gpa_allocator),
        .delta_time = 0.0,
        .total_time = 0.0,
        .data = data,
    };
    defer {
        for (context.depth_images.items) |depth_image| {
            depth_image.deinit();
        }
        context.depth_images.deinit();

        var it = context.pipelines.iterator();
        while (it.next()) |entry| {
            gfx.destroyPipeline(entry.value_ptr.*);
        }

        context.pipelines.deinit();
    }
    defer deinit_callback(&context);

    const start_time = std.time.microTimestamp();
    var last_current_time = start_time;

    while (!platform.shouldCloseWindow(window_handle)) {
        defer _ = arena.reset(.retain_capacity);

        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        context.delta_time = delta_time;
        context.total_time += delta_time;

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        try update_callback(&context);

        {
            imgui.beginFrame(
                context.delta_time,
                .{
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
                },
            );
            defer imgui.endFrame();

            try update_ui_callback(&context);
        }

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };
    }
}
