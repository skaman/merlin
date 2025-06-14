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
    msaa_samples: gfx.SampleCount,
};

pub const ModelViewProj = struct {
    model: zmath.Mat align(16),
    view: zmath.Mat align(16),
    proj: zmath.Mat align(16),
};

pub const OrbitCamera = struct {
    position: zmath.Vec,
    target: zmath.Vec,
    up: zmath.Vec,

    fov_y: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32,

    view: zmath.Mat align(16),
    proj: zmath.Mat align(16),

    pub fn init(position: zmath.Vec, target: zmath.Vec) OrbitCamera {
        return .{
            .position = position,
            .target = target,
            .up = zmath.f32x4(0.0, -1.0, 0.0, 0.0),
            .fov_y = std.math.rad_per_deg * 45.0,
            .aspect_ratio = 16.0 / 9.0,
            .near_plane = 0.1,
            .far_plane = 1000.0,
            .view = zmath.identity(),
            .proj = zmath.identity(),
        };
    }

    pub fn setPosition(self: *OrbitCamera, position: zmath.Vec) void {
        self.position = position;
    }

    pub fn setTarget(self: *OrbitCamera, target: zmath.Vec) void {
        self.target = target;
    }

    pub fn setAspectRatio(self: *OrbitCamera, aspect_ratio: f32) void {
        self.aspect_ratio = aspect_ratio;
    }

    pub fn update(self: *OrbitCamera) void {
        self.view = zmath.lookAtLh(self.position, self.target, self.up);
        self.proj = zmath.perspectiveFovLh(
            self.fov_y,
            self.aspect_ratio,
            self.near_plane,
            self.far_plane,
        );
    }

    pub fn getViewMatrix(self: *const OrbitCamera) zmath.Mat {
        return self.view;
    }

    pub fn getProjectionMatrix(self: *const OrbitCamera) zmath.Mat {
        return self.proj;
    }
};

const DepthImage = struct {
    handle: gfx.ImageHandle,
    view_handle: gfx.ImageViewHandle,

    pub fn deinit(self: *const DepthImage) void {
        gfx.destroyImageView(self.view_handle);
        gfx.destroyImage(self.handle);
    }
};

const ColorImage = struct {
    handle: gfx.ImageHandle,
    view_handle: gfx.ImageViewHandle,

    pub fn deinit(self: *const ColorImage) void {
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
        tex_sampler_uniform_handle: gfx.NameHandle,
        color_images: std.ArrayList(ColorImage),
        color_image_size: [2]u32,
        color_image_format: gfx.ImageFormat,
        depth_images: std.ArrayList(DepthImage),
        depth_image_size: [2]u32,
        depth_image_format: gfx.ImageFormat,
        msaa_samples: gfx.SampleCount,
        pipelines: std.AutoHashMap(PipelineKey, gfx.PipelineHandle),
        delta_time: f32,
        total_time: f32,
        data: T,

        pub fn getColorImage(self: *Context(T)) !ColorImage {
            const swapchain_size = gfx.getSwapchainSize(self.framebuffer_handle);
            if (self.color_images.items.len == 0 or
                self.color_image_size[0] != swapchain_size[0] or
                self.color_image_size[1] != swapchain_size[1])
            {
                for (self.color_images.items) |color_image| {
                    color_image.deinit();
                }
                self.color_images.clearRetainingCapacity();

                const max_frames_in_flight = gfx.getMaxFramesInFlight();
                for (0..max_frames_in_flight) |_| {
                    const color_image_handle = try gfx.createImage(.{
                        .format = self.color_image_format,
                        .width = swapchain_size[0],
                        .height = swapchain_size[1],
                        .usage = .{ .color_attachment = true },
                        .samples = self.msaa_samples,
                    });
                    errdefer gfx.destroyImage(color_image_handle);

                    const color_image_view_handle = try gfx.createImageView(
                        color_image_handle,
                        .{
                            .format = self.color_image_format,
                            .aspect = .{ .color = true },
                        },
                    );
                    errdefer gfx.destroyImageView(color_image_view_handle);

                    try self.color_images.append(.{
                        .handle = color_image_handle,
                        .view_handle = color_image_view_handle,
                    });
                }

                self.color_image_size = swapchain_size;
            }

            const current_frame_in_flight = gfx.getCurrentFrameInFlight();
            return self.color_images.items[current_frame_in_flight];
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
                for (0..max_frames_in_flight) |_| {
                    const depth_image_handle = try gfx.createImage(.{
                        .format = self.depth_image_format,
                        .width = swapchain_size[0],
                        .height = swapchain_size[1],
                        .usage = .{ .depth_stencil_attachment = true },
                        .samples = self.msaa_samples,
                    });
                    errdefer gfx.destroyImage(depth_image_handle);

                    const depth_image_view_handle = try gfx.createImageView(
                        depth_image_handle,
                        .{
                            .format = self.depth_image_format,
                            .aspect = .{ .depth = true },
                        },
                    );
                    errdefer gfx.destroyImageView(depth_image_view_handle);

                    try self.depth_images.append(.{
                        .handle = depth_image_handle,
                        .view_handle = depth_image_view_handle,
                    });
                }

                self.depth_image_size = swapchain_size;
            }

            const current_frame_in_flight = gfx.getCurrentFrameInFlight();
            return self.depth_images.items[current_frame_in_flight];
        }

        pub fn getColorAttachment(
            self: *Context(T),
            with_mssa: bool,
            load_op: gfx.AttachmentLoadOp,
            store_op: gfx.AttachmentStoreOp,
        ) !gfx.Attachment {
            var color_attachment: gfx.Attachment = undefined;
            if (with_mssa and @intFromEnum(self.msaa_samples) > @intFromEnum(gfx.SampleCount.one)) {
                const color_image = try self.getColorImage();
                color_attachment = .{
                    .image = color_image.handle,
                    .image_view = color_image.view_handle,
                    .resolve_mode = .average,
                    .resolve_image = gfx.getSurfaceImage(self.framebuffer_handle),
                    .resolve_image_view = gfx.getSurfaceImageView(self.framebuffer_handle),
                    .format = gfx.getSurfaceColorFormat(),
                    .load_op = load_op,
                    .store_op = store_op,
                };
            } else {
                color_attachment = .{
                    .image = gfx.getSurfaceImage(self.framebuffer_handle),
                    .image_view = gfx.getSurfaceImageView(self.framebuffer_handle),
                    .format = gfx.getSurfaceColorFormat(),
                    .load_op = load_op,
                    .store_op = store_op,
                };
            }

            return color_attachment;
        }

        pub fn getDepthAttachment(self: *Context(T)) !gfx.Attachment {
            const depth_image = try self.getDepthImage();
            return .{
                .image = depth_image.handle,
                .image_view = depth_image.view_handle,
                .format = self.depth_image_format,
                .load_op = .clear,
                .store_op = .dont_care,
            };
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
                    .multisample = .{
                        .sample_count = self.msaa_samples,
                    },
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
            model: zmath.Mat,
            view: zmath.Mat,
            proj: zmath.Mat,
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

            pushConstantsMvp(
                model,
                view,
                proj,
                .vertex,
                0,
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

pub fn pushConstantsMvp(
    model: zmath.Mat,
    view: zmath.Mat,
    proj: zmath.Mat,
    shader_stage: utils.gfx_types.ShaderType,
    offset: u32,
) void {
    const mvp = ModelViewProj{
        .model = model,
        .view = view,
        .proj = proj,
    };
    const mvp_ptr: [*]const u8 = @ptrCast(&mvp);
    gfx.pushConstants(
        shader_stage,
        offset,
        mvp_ptr[0..@sizeOf(ModelViewProj)],
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

    const supported_sample_counts = gfx.getSupportedSampleCounts();
    const msaa_samples = supported_sample_counts[
        supported_sample_counts.len - 1
    ];

    const data = try init_callback(.{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .window_handle = window_handle,
        .framebuffer_handle = framebuffer_handle,
        .msaa_samples = msaa_samples,
    });

    // Uniforms
    const tex_sampler_uniform_handle = gfx.nameHandle("u_tex_sampler");

    var context = Context(T){
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .window_handle = window_handle,
        .framebuffer_handle = framebuffer_handle,
        .tex_sampler_uniform_handle = tex_sampler_uniform_handle,
        .color_images = .init(gpa_allocator),
        .color_image_size = [_]u32{ 0, 0 },
        .color_image_format = gfx.getSurfaceColorFormat(),
        .depth_images = .init(gpa_allocator),
        .depth_image_size = [_]u32{ 0, 0 },
        .depth_image_format = gfx.getSurfaceDepthFormat(),
        .msaa_samples = msaa_samples,
        .pipelines = .init(gpa_allocator),
        .delta_time = 0.0,
        .total_time = 0.0,
        .data = data,
    };
    defer {
        for (context.color_images.items) |color_image| {
            color_image.deinit();
        }
        context.color_images.deinit();

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
