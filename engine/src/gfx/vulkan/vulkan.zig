const std = @import("std");
const builtin = @import("builtin");

const shared = @import("shared");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
pub const Buffer = @import("buffer.zig").Buffer;
pub const CommandQueue = @import("command_queue.zig").CommandQueue;
pub const Device = @import("device.zig").Device;
pub const Instance = @import("instance.zig").Instance;
pub const Library = @import("library.zig").Library;
pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Program = @import("program.zig").Program;
pub const RenderPass = @import("render_pass.zig").RenderPass;
pub const Shader = @import("shader.zig").Shader;
pub const Surface = @import("surface.zig").Surface;
pub const SwapChain = @import("swap_chain.zig").nSwapChain;
pub const SwapChainSupportDetails = @import("swap_chain.zig").SwapChainSupportDetails;
pub const VertexBuffer = @import("vertex_buffer.zig").VertexBuffer;

pub const log = std.log.scoped(.gfx_vk);

pub fn debugCallback(
    message_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    p_callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = p_user_data;

    const allowed_flags = c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    if (message_type & allowed_flags == 0) {
        return c.VK_FALSE;
    }

    if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        log.err("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        log.warn("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
        log.info("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) {
        log.debug("{s}", .{p_callback_data.*.pMessage});
    }

    return c.VK_FALSE;
}

pub fn prepareValidationLayers(
    allocator: std.mem.Allocator,
    options: *const gfx.GraphicsOptions,
) !std.ArrayList([*:0]const u8) {
    var layers = std.ArrayList([*:0]const u8).init(
        allocator,
    );
    errdefer layers.deinit();

    if (options.enable_vulkan_debug) {
        try layers.append("VK_LAYER_KHRONOS_validation");
    }

    return layers;
}

pub fn getPhysicalDeviceTypeLabel(device_type: c.VkPhysicalDeviceType) []const u8 {
    return switch (device_type) {
        c.VK_PHYSICAL_DEVICE_TYPE_OTHER => "Other",
        c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
        else => unreachable,
    };
}

pub fn checkVulkanError(comptime message: []const u8, result: c.VkResult) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_TIMEOUT => {
            log.err("{s}: timeout", .{message});
            return error.VulkanTimeout;
        },
        c.VK_NOT_READY => {
            log.err("{s}: not ready", .{message});
            return error.VulkanNotReady;
        },
        c.VK_SUBOPTIMAL_KHR => {
            log.err("{s}: suboptimal", .{message});
            return error.VulkanSuboptimal;
        },
        c.VK_ERROR_OUT_OF_HOST_MEMORY => {
            log.err("{s}: out of host memory", .{message});
            return error.VulkanOutOfHostMemory;
        },
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => {
            log.err("{s}: out of device memory", .{message});
            return error.VulkanOutOfDeviceMemory;
        },
        c.VK_ERROR_INITIALIZATION_FAILED => {
            log.err("{s}: initialization failed", .{message});
            return error.VulkanInitializationFailed;
        },
        c.VK_ERROR_LAYER_NOT_PRESENT => {
            log.err("{s}: layer not present", .{message});
            return error.VulkanLayerNotPresent;
        },
        c.VK_ERROR_EXTENSION_NOT_PRESENT => {
            log.err("{s}: extension not present", .{message});
            return error.VulkanExtensionNotPresent;
        },
        c.VK_ERROR_FEATURE_NOT_PRESENT => {
            log.err("{s}: feature not present", .{message});
            return error.VulkanFeatureNotPresent;
        },
        c.VK_ERROR_INCOMPATIBLE_DRIVER => {
            log.err("{s}: incompatible driver", .{message});
            return error.VulkanIncompatibleDriver;
        },
        c.VK_ERROR_TOO_MANY_OBJECTS => {
            log.err("{s}: too many objects", .{message});
            return error.VulkanTooManyObjects;
        },
        c.VK_ERROR_DEVICE_LOST => {
            log.err("{s}: device lost", .{message});
            return error.VulkanDeviceLost;
        },
        c.VK_ERROR_SURFACE_LOST_KHR => {
            log.err("{s}: surface lost", .{message});
            return error.VulkanSurfaceLost;
        },
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => {
            log.err("{s}: native window in use", .{message});
            return error.VulkanNativeWindowInUse;
        },
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => {
            log.err("{s}: compression exhausted", .{message});
            return error.VulkanCompressionExhausted;
        },
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR => {
            log.err("{s}: invalid opaque capture address", .{message});
            return error.VulkanInvalidOpaqueCaptureAddress;
        },
        c.VK_ERROR_INVALID_SHADER_NV => {
            log.err("{s}: invalid shader", .{message});
            return error.VulkanInvalidShader;
        },
        c.VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT => {
            log.err("{s}: full screen exclusive mode lost", .{message});
            return error.VulkanFullScreenExclusiveModeLost;
        },
        else => {
            log.err("{s}: {d}", .{ message, result });
            return error.VulkanUnknownError;
        },
    };
}

pub const MaxFramesInFlight = 2;

const PipelineKey = struct {
    program: gfx.ProgramHandle,
    layout: shared.VertexLayout,
};

const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    library: Library,
    instance: *Instance,
    device: *Device,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    surface: *Surface,
    swap_chain: *SwapChain,
    main_render_pass: *RenderPass,
    command_queue: *CommandQueue,
    debug_messenger: ?c.VkDebugUtilsMessengerEXT,
    options: gfx.GraphicsOptions,

    shader_modules: [gfx.MaxShaderHandles]Shader,
    programs: [gfx.MaxProgramHandles]Program,
    pipelines: std.AutoHashMap(PipelineKey, Pipeline),
    vertex_buffers: [gfx.MaxVertexBufferHandles]VertexBuffer,

    vertex_buffers_to_destroy: [gfx.MaxProgramHandles]VertexBuffer,
    vertex_buffers_to_destroy_count: u32,

    image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore,
    render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore,
    in_flight_fences: [MaxFramesInFlight]c.VkFence,

    current_image_index: u32,
    current_frame: u32,
    current_program: ?gfx.ProgramHandle,
    current_vertex_buffer: ?gfx.VertexBufferHandle,

    framebuffer_invalidated: bool,

    fn init(graphics_ctx: *const gfx.GraphicsContext) !Self {
        var library = try Library.init();
        errdefer library.deinit();

        var instance = try graphics_ctx.allocator.create(Instance);
        errdefer graphics_ctx.allocator.destroy(instance);

        instance.* = try Instance.init(
            graphics_ctx.allocator,
            graphics_ctx.options,
            &library,
            null,
        );
        errdefer instance.deinit();

        const debug_messenger = try setupDebugMessenger(
            &graphics_ctx.options,
            instance,
        );

        var surface = try graphics_ctx.allocator.create(Surface);
        errdefer graphics_ctx.allocator.destroy(surface);

        surface.* = try Surface.init(
            graphics_ctx,
            &library,
            instance,
        );
        errdefer surface.deinit();

        var device = try graphics_ctx.allocator.create(Device);
        errdefer graphics_ctx.allocator.destroy(device);

        device.* = try Device.init(
            graphics_ctx,
            &library,
            instance,
            surface,
        );
        errdefer device.deinit();

        var graphics_queue: c.VkQueue = undefined;
        device.getDeviceQueue(
            device.queue_family_indices.graphics_family.?,
            0,
            &graphics_queue,
        );

        var present_queue: c.VkQueue = undefined;
        device.getDeviceQueue(
            device.queue_family_indices.present_family.?,
            0,
            &present_queue,
        );

        var swap_chain = try graphics_ctx.allocator.create(SwapChain);
        errdefer graphics_ctx.allocator.destroy(swap_chain);

        swap_chain.* = try SwapChain.init(
            graphics_ctx.allocator,
            instance,
            device,
            surface,
            graphics_ctx.options.window,
        );
        errdefer swap_chain.deinit();

        var main_render_pass = try graphics_ctx.allocator.create(RenderPass);
        errdefer graphics_ctx.allocator.destroy(main_render_pass);

        main_render_pass.* = try RenderPass.init(
            device,
            swap_chain.format,
        );
        errdefer main_render_pass.deinit();

        try swap_chain.createFrameBuffers(main_render_pass);

        var command_queue = try graphics_ctx.allocator.create(CommandQueue);
        errdefer graphics_ctx.allocator.destroy(command_queue);

        command_queue.* = try CommandQueue.init(&library, device);
        errdefer command_queue.deinit();

        const semaphore_create_info = std.mem.zeroInit(
            c.VkSemaphoreCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            },
        );

        const fence_create_info = std.mem.zeroInit(
            c.VkFenceCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
            },
        );

        var image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
        var render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
        var in_flight_fences: [MaxFramesInFlight]c.VkFence = undefined;

        for (0..MaxFramesInFlight) |i| {
            try device.createSemaphore(
                &semaphore_create_info,
                &image_available_semaphores[i],
            );

            try device.createSemaphore(
                &semaphore_create_info,
                &render_finished_semaphores[i],
            );

            try device.createFence(
                &fence_create_info,
                &in_flight_fences[i],
            );
        }

        return .{
            .allocator = graphics_ctx.allocator,
            .library = library,
            .instance = instance,
            .debug_messenger = debug_messenger,
            .options = graphics_ctx.options,
            .device = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .surface = surface,
            .swap_chain = swap_chain,
            .main_render_pass = main_render_pass,
            .command_queue = command_queue,
            .shader_modules = undefined,
            .programs = undefined,
            .pipelines = .init(graphics_ctx.allocator),
            .vertex_buffers = undefined,
            .vertex_buffers_to_destroy = undefined,
            .vertex_buffers_to_destroy_count = 0,
            .image_available_semaphores = image_available_semaphores,
            .render_finished_semaphores = render_finished_semaphores,
            .in_flight_fences = in_flight_fences,
            .current_image_index = 0,
            .current_frame = 0,
            .current_program = null,
            .current_vertex_buffer = null,
            .framebuffer_invalidated = false,
        };
    }

    fn deinit(self: *Self) void {
        self.device.waitIdle() catch {
            log.err("Failed to wait for Vulkan device to become idle", .{});
        };

        self.cleanUpVertexBuffers();

        for (0..MaxFramesInFlight) |i| {
            self.device.destroySemaphore(self.image_available_semaphores[i]);
            self.device.destroySemaphore(self.render_finished_semaphores[i]);
            self.device.destroyFence(self.in_flight_fences[i]);
        }

        var iterator = self.pipelines.valueIterator();
        while (iterator.next()) |pipeline| {
            pipeline.deinit();
        }
        self.pipelines.deinit();

        self.command_queue.deinit();
        self.allocator.destroy(self.command_queue);

        self.main_render_pass.deinit();
        self.allocator.destroy(self.main_render_pass);

        self.swap_chain.deinit();
        self.allocator.destroy(self.swap_chain);

        self.surface.deinit();
        self.allocator.destroy(self.surface);

        self.device.deinit();
        self.allocator.destroy(self.device);

        if (self.debug_messenger) |debug_messenger| {
            self.instance.destroyDebugUtilsMessengerEXT(debug_messenger);
        }
        self.instance.deinit();
        self.allocator.destroy(self.instance);

        self.library.deinit();
    }

    fn cleanUpVertexBuffers(self: *Self) void {
        for (0..self.vertex_buffers_to_destroy_count) |i| {
            self.vertex_buffers_to_destroy[i].deinit();
        }
        self.vertex_buffers_to_destroy_count = 0;
    }

    fn setupDebugMessenger(options: *const gfx.GraphicsOptions, instance: *Instance) !?c.VkDebugUtilsMessengerEXT {
        if (!options.enable_vulkan_debug) {
            return null;
        }

        const create_info = std.mem.zeroInit(
            c.VkDebugUtilsMessengerCreateInfoEXT,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                .pfnUserCallback = @as(c.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&debugCallback)),
            },
        );

        var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;
        try instance.createDebugUtilsMessengerEXT(
            &create_info,
            &debug_messenger,
        );
        return debug_messenger;
    }

    fn recreateSwapChain(self: *Self) !void {
        self.device.waitIdle() catch {
            log.err("Failed to wait for Vulkan device to become idle", .{});
        };

        self.swap_chain.deinit();
        self.allocator.destroy(self.swap_chain);

        self.swap_chain = try self.allocator.create(SwapChain);
        self.swap_chain.* = try SwapChain.init(
            self.allocator,
            self.instance,
            self.device,
            self.surface,
            self.options.window,
        );

        try self.swap_chain.createFrameBuffers(self.main_render_pass);
    }
};

var context: Context = undefined;

pub const Renderer = struct {
    pub fn init(graphics_ctx: *const gfx.GraphicsContext) !Renderer {
        log.debug("Initializing Vulkan renderer...", .{});

        context = try .init(graphics_ctx);

        return .{};
    }

    pub fn deinit(_: *const Renderer) void {
        log.debug("Deinitializing Vulkan renderer...", .{});

        context.deinit();
    }

    pub fn getSwapchainSize(_: *const Renderer) gfx.Size {
        return .{
            .width = @as(f32, @floatFromInt(context.swap_chain.extent.width)),
            .height = @as(f32, @floatFromInt(context.swap_chain.extent.height)),
        };
    }

    pub fn invalidateFramebuffer(_: *const Renderer) void {
        context.framebuffer_invalidated = true;
    }

    pub fn createShader(
        _: *const Renderer,
        handle: gfx.ShaderHandle,
        data: *const shared.ShaderData,
    ) !void {
        context.shader_modules[handle] = try Shader.init(context.device, data);

        log.debug("Created Vulkan shader module: {d}", .{handle});
    }

    pub fn destroyShader(
        _: *Renderer,
        handle: gfx.ShaderHandle,
    ) void {
        context.shader_modules[handle].deinit();

        log.debug("Destroyed Vulkan shader module: {d}", .{handle});
    }

    pub fn createProgram(
        _: *const Renderer,
        handle: gfx.ProgramHandle,
        vertex_shader: gfx.ShaderHandle,
        fragment_shader: gfx.ShaderHandle,
    ) !void {
        context.programs[handle] = try Program.init(
            context.device,
            &context.shader_modules[vertex_shader],
            &context.shader_modules[fragment_shader],
        );

        log.debug("Created Vulkan program: {d}", .{handle});
    }

    pub fn destroyProgram(
        _: *const Renderer,
        handle: gfx.ProgramHandle,
    ) void {
        context.programs[handle].deinit();
        log.debug("Destroyed Vulkan program: {d}", .{handle});
    }

    pub fn createVertexBuffer(
        _: *const Renderer,
        handle: gfx.VertexBufferHandle,
        data: [*]const u8,
        size: u32,
        layout: shared.VertexLayout,
    ) !void {
        context.vertex_buffers[handle] = try VertexBuffer.init(
            context.device,
            layout,
            data,
            size,
        );

        log.debug("Created Vulkan vertex buffer: {d}", .{handle});
    }

    pub fn destroyVertexBuffer(
        _: *const Renderer,
        handle: gfx.VertexBufferHandle,
    ) void {
        context.vertex_buffers_to_destroy[context.vertex_buffers_to_destroy_count] = context.vertex_buffers[handle];
        context.vertex_buffers_to_destroy_count += 1;
        log.debug("Destroyed Vulkan vertex buffer: {d}", .{handle});
    }

    pub fn beginFrame(_: *const Renderer) !bool {
        try context.device.waitForFences(
            1,
            &context.in_flight_fences[context.current_frame],
            c.VK_TRUE,
            c.UINT64_MAX,
        );

        if (try context.device.acquireNextImageKHR(
            context.swap_chain.handle,
            c.UINT64_MAX,
            context.image_available_semaphores[context.current_frame],
            null,
            &context.current_image_index,
        ) == c.VK_ERROR_OUT_OF_DATE_KHR) {
            try context.recreateSwapChain();
            return false;
        }

        try context.device.resetFences(1, &context.in_flight_fences[context.current_frame]);

        try context.command_queue.reset(context.current_frame);
        context.cleanUpVertexBuffers();
        try context.command_queue.begin(context.current_frame);

        context.command_queue.beginRenderPass(
            context.main_render_pass.handle,
            context.swap_chain.frame_buffers.?[context.current_image_index],
            context.swap_chain.extent,
            context.current_frame,
        );

        return true;
    }

    pub fn endFrame(_: *const Renderer) !void {
        context.command_queue.endRenderPass(context.current_frame);
        try context.command_queue.end(context.current_frame);

        const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const wait_semaphores = [_]c.VkSemaphore{context.image_available_semaphores[context.current_frame]};
        const signal_semaphores = [_]c.VkSemaphore{context.render_finished_semaphores[context.current_frame]};
        const submit_info = std.mem.zeroInit(
            c.VkSubmitInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &wait_semaphores,
                .pWaitDstStageMask = &wait_stages,
                .commandBufferCount = 1,
                .pCommandBuffers = &context.command_queue.command_buffers[context.current_frame],
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = &signal_semaphores,
            },
        );

        try context.device.queueSubmit(
            context.graphics_queue,
            1,
            &submit_info,
            context.in_flight_fences[context.current_frame],
        );

        const present_info = std.mem.zeroInit(
            c.VkPresentInfoKHR,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &signal_semaphores,
                .swapchainCount = 1,
                .pSwapchains = &context.swap_chain.handle,
                .pImageIndices = &context.current_image_index,
            },
        );

        const result = try context.device.queuePresentKHR(context.present_queue, &present_info);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or context.framebuffer_invalidated) {
            context.framebuffer_invalidated = false;
            try context.recreateSwapChain();
        }

        context.current_frame = (context.current_frame + 1) % MaxFramesInFlight;
    }

    pub fn setViewport(_: *const Renderer, viewport: gfx.Rect) void {
        const vk_viewport = std.mem.zeroInit(
            c.VkViewport,
            .{
                .x = @as(f32, viewport.position.x),
                .y = @as(f32, viewport.position.y),
                .width = @as(f32, viewport.size.width),
                .height = @as(f32, viewport.size.height),
                .minDepth = 0,
                .maxDepth = 1,
            },
        );
        context.command_queue.setViewport(vk_viewport, context.current_frame);
    }

    pub fn setScissor(_: *const Renderer, scissor: gfx.Rect) void {
        const vk_scissor = std.mem.zeroInit(
            c.VkRect2D,
            .{
                .offset = c.VkOffset2D{
                    .x = @as(i32, @intFromFloat(scissor.position.x)),
                    .y = @as(i32, @intFromFloat(scissor.position.y)),
                },
                .extent = c.VkExtent2D{
                    .width = @as(u32, @intFromFloat(scissor.size.width)),
                    .height = @as(u32, @intFromFloat(scissor.size.height)),
                },
            },
        );
        context.command_queue.setScissor(vk_scissor, context.current_frame);
    }

    pub fn bindProgram(_: *const Renderer, program: gfx.ProgramHandle) void {
        context.current_program = program;
    }

    pub fn bindVertexBuffer(_: *const Renderer, vertex_buffer: gfx.VertexBufferHandle) void {
        context.current_vertex_buffer = vertex_buffer;
    }

    pub fn draw(
        self: *const Renderer,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        std.debug.assert(context.current_program != null);
        std.debug.assert(context.current_vertex_buffer != null);

        const vertex_buffer = &context.vertex_buffers[context.current_vertex_buffer.?];
        const pipeline = self.getPipeline(context.current_program.?, &vertex_buffer.layout) catch {
            log.err("Failed to bind Vulkan program: {d}", .{context.current_program.?});
            return;
        };
        context.command_queue.bindPipeline(pipeline.handle, context.current_frame);

        context.command_queue.bindVertexBuffer(
            vertex_buffer.buffer.handle,
            0,
            context.current_frame,
        );

        context.command_queue.draw(
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
            context.current_frame,
        );
    }

    fn getPipeline(
        _: *const Renderer,
        program: gfx.ProgramHandle,
        layout: *shared.VertexLayout,
    ) !Pipeline {
        const key = PipelineKey{
            .program = program,
            .layout = layout.*,
        };
        var pipeline = context.pipelines.get(key);
        if (pipeline != null) {
            return pipeline.?;
        }

        pipeline = try Pipeline.init(
            context.device,
            &context.programs[program],
            context.main_render_pass,
            layout.*,
        );
        try context.pipelines.put(key, pipeline.?);
        return pipeline.?;
    }
};
