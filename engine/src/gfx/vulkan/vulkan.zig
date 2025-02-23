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

pub const MaxFramesInFlight = 2;

const PipelineKey = struct {
    program: gfx.ProgramHandle,
    layout: shared.VertexLayout,
};

var g_allocator: std.mem.Allocator = undefined;
var g_options: gfx.GraphicsOptions = undefined;
var g_library: Library = undefined;
var g_instance: *Instance = undefined;
var g_device: *Device = undefined;
var g_graphics_queue: c.VkQueue = undefined;
var g_present_queue: c.VkQueue = undefined;
var g_surface: *Surface = undefined;
var g_swap_chain: *SwapChain = undefined;
var g_main_render_pass: *RenderPass = undefined;
var g_command_queue: *CommandQueue = undefined;
var g_debug_messenger: ?c.VkDebugUtilsMessengerEXT = null;

var g_shader_modules: [gfx.MaxShaderHandles]Shader = undefined;
var g_programs: [gfx.MaxProgramHandles]Program = undefined;
var g_pipelines: std.AutoHashMap(PipelineKey, Pipeline) = undefined;
var g_vertex_buffers: [gfx.MaxVertexBufferHandles]VertexBuffer = undefined;

var g_vertex_buffers_to_destroy: [gfx.MaxProgramHandles]VertexBuffer = undefined;
var g_vertex_buffers_to_destroy_count: u32 = 0;

var g_image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var g_render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var g_in_flight_fences: [MaxFramesInFlight]c.VkFence = undefined;

var g_current_image_index: u32 = 0;
var g_current_frame: u32 = 0;
var g_current_program: ?gfx.ProgramHandle = null;
var g_current_vertex_buffer: ?gfx.VertexBufferHandle = null;

var g_framebuffer_invalidated: bool = false;

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

fn cleanUpVertexBuffers() void {
    for (0..g_vertex_buffers_to_destroy_count) |i| {
        g_vertex_buffers_to_destroy[i].deinit();
    }
    g_vertex_buffers_to_destroy_count = 0;
}

fn recreateSwapChain() !void {
    g_device.waitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    g_swap_chain.deinit();
    g_allocator.destroy(g_swap_chain);

    g_swap_chain = try g_allocator.create(SwapChain);
    g_swap_chain.* = try SwapChain.init(
        g_allocator,
        g_instance,
        g_device,
        g_surface,
        g_options.window,
    );

    try g_swap_chain.createFrameBuffers(g_main_render_pass);
}

fn getPipeline(
    program: gfx.ProgramHandle,
    layout: *shared.VertexLayout,
) !Pipeline {
    const key = PipelineKey{
        .program = program,
        .layout = layout.*,
    };
    var pipeline = g_pipelines.get(key);
    if (pipeline != null) {
        return pipeline.?;
    }

    pipeline = try Pipeline.init(
        g_device,
        &g_programs[program],
        g_main_render_pass,
        layout.*,
    );
    try g_pipelines.put(key, pipeline.?);
    return pipeline.?;
}

pub fn init(graphics_ctx: *const gfx.GraphicsContext) !void {
    log.debug("Initializing Vulkan renderer...", .{});

    g_allocator = graphics_ctx.allocator;
    g_options = graphics_ctx.options;

    g_library = try Library.init();
    errdefer g_library.deinit();

    g_instance = try g_allocator.create(Instance);
    errdefer g_allocator.destroy(g_instance);

    g_instance.* = try Instance.init(
        g_allocator,
        &g_options,
        &g_library,
        null,
    );
    errdefer g_instance.deinit();

    g_debug_messenger = try setupDebugMessenger(
        &g_options,
        g_instance,
    );

    g_surface = try g_allocator.create(Surface);
    errdefer g_allocator.destroy(g_surface);

    g_surface.* = try Surface.init(
        &g_options,
        &g_library,
        g_instance,
    );
    errdefer g_surface.deinit();

    g_device = try g_allocator.create(Device);
    errdefer g_allocator.destroy(g_device);

    g_device.* = try Device.init(
        g_allocator,
        &g_options,
        &g_library,
        g_instance,
        g_surface,
    );
    errdefer g_device.deinit();

    g_device.getDeviceQueue(
        g_device.queue_family_indices.graphics_family.?,
        0,
        &g_graphics_queue,
    );

    g_device.getDeviceQueue(
        g_device.queue_family_indices.present_family.?,
        0,
        &g_present_queue,
    );

    g_swap_chain = try g_allocator.create(SwapChain);
    errdefer g_allocator.destroy(g_swap_chain);

    g_swap_chain.* = try SwapChain.init(
        g_allocator,
        g_instance,
        g_device,
        g_surface,
        g_options.window,
    );
    errdefer g_swap_chain.deinit();

    g_main_render_pass = try g_allocator.create(RenderPass);
    errdefer g_allocator.destroy(g_main_render_pass);

    g_main_render_pass.* = try RenderPass.init(
        g_device,
        g_swap_chain.format,
    );
    errdefer g_main_render_pass.deinit();

    try g_swap_chain.createFrameBuffers(g_main_render_pass);

    g_command_queue = try g_allocator.create(CommandQueue);
    errdefer g_allocator.destroy(g_command_queue);

    g_command_queue.* = try CommandQueue.init(&g_library, g_device);
    errdefer g_command_queue.deinit();

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

    for (0..MaxFramesInFlight) |i| {
        try g_device.createSemaphore(
            &semaphore_create_info,
            &g_image_available_semaphores[i],
        );

        try g_device.createSemaphore(
            &semaphore_create_info,
            &g_render_finished_semaphores[i],
        );

        try g_device.createFence(
            &fence_create_info,
            &g_in_flight_fences[i],
        );
    }

    g_pipelines = .init(g_allocator);
}

pub fn deinit() void {
    log.debug("Deinitializing Vulkan renderer...", .{});

    g_device.waitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    cleanUpVertexBuffers();

    for (0..MaxFramesInFlight) |i| {
        g_device.destroySemaphore(g_image_available_semaphores[i]);
        g_device.destroySemaphore(g_render_finished_semaphores[i]);
        g_device.destroyFence(g_in_flight_fences[i]);
    }

    var iterator = g_pipelines.valueIterator();
    while (iterator.next()) |pipeline| {
        pipeline.deinit();
    }
    g_pipelines.deinit();

    g_command_queue.deinit();
    g_allocator.destroy(g_command_queue);

    g_main_render_pass.deinit();
    g_allocator.destroy(g_main_render_pass);

    g_swap_chain.deinit();
    g_allocator.destroy(g_swap_chain);

    g_surface.deinit();
    g_allocator.destroy(g_surface);

    g_device.deinit();
    g_allocator.destroy(g_device);

    if (g_debug_messenger) |debug_messenger| {
        g_instance.destroyDebugUtilsMessengerEXT(debug_messenger);
    }
    g_instance.deinit();
    g_allocator.destroy(g_instance);

    g_library.deinit();
}

pub fn getSwapchainSize() gfx.Size {
    return .{
        .width = @as(f32, @floatFromInt(g_swap_chain.extent.width)),
        .height = @as(f32, @floatFromInt(g_swap_chain.extent.height)),
    };
}

pub fn invalidateFramebuffer() void {
    g_framebuffer_invalidated = true;
}

pub fn createShader(
    handle: gfx.ShaderHandle,
    data: *const shared.ShaderData,
) !void {
    g_shader_modules[handle] = try Shader.init(g_device, data);

    log.debug("Created Vulkan shader module: {d}", .{handle});
}

pub fn destroyShader(
    handle: gfx.ShaderHandle,
) void {
    g_shader_modules[handle].deinit();

    log.debug("Destroyed Vulkan shader module: {d}", .{handle});
}

pub fn createProgram(
    handle: gfx.ProgramHandle,
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
) !void {
    g_programs[handle] = try Program.init(
        g_device,
        &g_shader_modules[vertex_shader],
        &g_shader_modules[fragment_shader],
    );

    log.debug("Created Vulkan program: {d}", .{handle});
}

pub fn destroyProgram(
    handle: gfx.ProgramHandle,
) void {
    g_programs[handle].deinit();
    log.debug("Destroyed Vulkan program: {d}", .{handle});
}

pub fn createVertexBuffer(
    handle: gfx.VertexBufferHandle,
    data: [*]const u8,
    size: u32,
    layout: shared.VertexLayout,
) !void {
    g_vertex_buffers[handle] = try VertexBuffer.init(
        g_device,
        layout,
        data,
        size,
    );

    log.debug("Created Vulkan vertex buffer: {d}", .{handle});
}

pub fn destroyVertexBuffer(
    handle: gfx.VertexBufferHandle,
) void {
    g_vertex_buffers_to_destroy[g_vertex_buffers_to_destroy_count] = g_vertex_buffers[handle];
    g_vertex_buffers_to_destroy_count += 1;
    log.debug("Destroyed Vulkan vertex buffer: {d}", .{handle});
}

pub fn beginFrame() !bool {
    try g_device.waitForFences(
        1,
        &g_in_flight_fences[g_current_frame],
        c.VK_TRUE,
        c.UINT64_MAX,
    );

    if (try g_device.acquireNextImageKHR(
        g_swap_chain.handle,
        c.UINT64_MAX,
        g_image_available_semaphores[g_current_frame],
        null,
        &g_current_image_index,
    ) == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try recreateSwapChain();
        return false;
    }

    try g_device.resetFences(1, &g_in_flight_fences[g_current_frame]);

    try g_command_queue.reset(g_current_frame);
    cleanUpVertexBuffers();
    try g_command_queue.begin(g_current_frame);

    g_command_queue.beginRenderPass(
        g_main_render_pass.handle,
        g_swap_chain.frame_buffers.?[g_current_image_index],
        g_swap_chain.extent,
        g_current_frame,
    );

    return true;
}

pub fn endFrame() !void {
    g_command_queue.endRenderPass(g_current_frame);
    try g_command_queue.end(g_current_frame);

    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const wait_semaphores = [_]c.VkSemaphore{g_image_available_semaphores[g_current_frame]};
    const signal_semaphores = [_]c.VkSemaphore{g_render_finished_semaphores[g_current_frame]};
    const submit_info = std.mem.zeroInit(
        c.VkSubmitInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &g_command_queue.command_buffers[g_current_frame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        },
    );

    try g_device.queueSubmit(
        g_graphics_queue,
        1,
        &submit_info,
        g_in_flight_fences[g_current_frame],
    );

    const present_info = std.mem.zeroInit(
        c.VkPresentInfoKHR,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &g_swap_chain.handle,
            .pImageIndices = &g_current_image_index,
        },
    );

    const result = try g_device.queuePresentKHR(g_present_queue, &present_info);
    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or g_framebuffer_invalidated) {
        g_framebuffer_invalidated = false;
        try recreateSwapChain();
    }

    g_current_frame = (g_current_frame + 1) % MaxFramesInFlight;
}

pub fn setViewport(viewport: gfx.Rect) void {
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
    g_command_queue.setViewport(vk_viewport, g_current_frame);
}

pub fn setScissor(scissor: gfx.Rect) void {
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
    g_command_queue.setScissor(vk_scissor, g_current_frame);
}

pub fn bindProgram(program: gfx.ProgramHandle) void {
    g_current_program = program;
}

pub fn bindVertexBuffer(vertex_buffer: gfx.VertexBufferHandle) void {
    g_current_vertex_buffer = vertex_buffer;
}

pub fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    std.debug.assert(g_current_program != null);
    std.debug.assert(g_current_vertex_buffer != null);

    const vertex_buffer = &g_vertex_buffers[g_current_vertex_buffer.?];
    const pipeline = getPipeline(g_current_program.?, &vertex_buffer.layout) catch {
        log.err("Failed to bind Vulkan program: {d}", .{g_current_program.?});
        return;
    };
    g_command_queue.bindPipeline(pipeline.handle, g_current_frame);

    g_command_queue.bindVertexBuffer(
        vertex_buffer.buffer.handle,
        0,
        g_current_frame,
    );

    g_command_queue.draw(
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
        g_current_frame,
    );
}
