const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const utils = @import("../../utils.zig");
const gfx = @import("../gfx.zig");
pub const buffer = @import("buffer.zig");
pub const command_buffers = @import("command_buffers.zig");
pub const command_pool = @import("command_pool.zig");
pub const device = @import("device.zig");
pub const index_buffers = @import("index_buffers.zig");
pub const instance = @import("instance.zig");
pub const library = @import("library.zig");
pub const pipeline = @import("pipeline.zig");
pub const programs = @import("programs.zig");
pub const render_pass = @import("render_pass.zig");
pub const shaders = @import("shaders.zig");
pub const surface = @import("surface.zig");
pub const swap_chain = @import("swap_chain.zig");
pub const textures = @import("textures.zig");
pub const uniform_buffer = @import("uniform_buffer.zig");
pub const uniform_registry = @import("uniform_registry.zig");
pub const vertex_buffers = @import("vertex_buffers.zig");

pub const log = std.log.scoped(.gfx_vk);

pub const MaxFramesInFlight = 2;
pub const MaxDescriptorSets = 1024;

const PipelineKey = struct {
    program: gfx.ProgramHandle,
    layout: gfx.VertexLayout,
};

var g_allocator: std.mem.Allocator = undefined;
var g_arena_allocator: std.mem.Allocator = undefined;
var g_options: gfx.Options = undefined;
var g_graphics_queue: c.VkQueue = undefined;
var g_present_queue: c.VkQueue = undefined;
var g_transfer_queue: c.VkQueue = undefined;
var g_surface: c.VkSurfaceKHR = undefined;
var g_swap_chain: swap_chain.SwapChain = undefined;
var g_main_render_pass: c.VkRenderPass = undefined;
var g_graphics_command_pool: c.VkCommandPool = undefined;
var g_transfer_command_pool: c.VkCommandPool = undefined;
var g_command_buffers: command_buffers.CommandBuffers = undefined;
var g_debug_messenger: ?c.VkDebugUtilsMessengerEXT = null;
var g_descriptor_pool: c.VkDescriptorPool = undefined;

var g_pipelines: std.AutoHashMap(PipelineKey, c.VkPipeline) = undefined;

var g_image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var g_render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var g_in_flight_fences: [MaxFramesInFlight]c.VkFence = undefined;

var g_current_image_index: u32 = 0;
var g_current_frame: u32 = 0;
var g_current_program: ?gfx.ProgramHandle = null;
var g_current_vertex_buffer: ?gfx.VertexBufferHandle = null;
var g_current_index_buffer: ?gfx.IndexBufferHandle = null;

var g_framebuffer_width: u32 = 0;
var g_framebuffer_height: u32 = 0;
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
    options: *const gfx.Options,
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

pub fn checkVulkanError(comptime message: []const u8, result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) {
        log.err("{s}: {s}", .{ message, c.string_VkResult(result) });
        return error.VulkanError;
    }
}

fn setupDebugMessenger(options: *const gfx.Options) !?c.VkDebugUtilsMessengerEXT {
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

fn destroyPendingResources() void {
    vertex_buffers.destroyPendingResources();
    index_buffers.destroyPendingResources();
    programs.destroyPendingResources();
    shaders.destroyPendingResources();
    textures.destroyPendingResources();
}

fn recreateSwapChain() !void {
    if (g_framebuffer_width == 0 or g_framebuffer_height == 0) {
        g_framebuffer_invalidated = true;
        return;
    }

    device.deviceWaitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    swap_chain.destroy(&g_swap_chain);
    g_swap_chain = try swap_chain.create(
        g_allocator,
        g_surface,
        g_framebuffer_width,
        g_framebuffer_height,
    );

    try swap_chain.createFrameBuffers(&g_swap_chain, g_main_render_pass);
}

fn getPipeline(
    program: gfx.ProgramHandle,
    layout: *gfx.VertexLayout,
) !c.VkPipeline {
    const key = PipelineKey{
        .program = program,
        .layout = layout.*,
    };
    var pipeline_value = g_pipelines.get(key);
    if (pipeline_value != null) {
        return pipeline_value.?;
    }

    pipeline_value = try pipeline.create(
        program,
        g_main_render_pass,
        layout.*,
    );
    try g_pipelines.put(key, pipeline_value.?);
    return pipeline_value.?;
}

pub fn init(
    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: *const gfx.Options,
) !void {
    log.debug("Initializing Vulkan renderer", .{});

    g_allocator = allocator;
    g_arena_allocator = arena_allocator;
    g_options = options.*;
    g_framebuffer_width = options.framebuffer_width;
    g_framebuffer_height = options.framebuffer_height;

    try library.init();
    errdefer library.deinit();

    try instance.init(g_allocator, &g_options);
    errdefer instance.deinit();

    g_debug_messenger = try setupDebugMessenger(&g_options);

    g_surface = try surface.create(&g_options);
    errdefer surface.destroy(g_surface);

    try device.init(g_allocator, &g_options, g_surface);
    errdefer device.deinit();

    device.getDeviceQueue(
        device.queue_family_indices.graphics_family.?,
        0,
        &g_graphics_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.present_family.?,
        0,
        &g_present_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.transfer_family.?,
        0,
        &g_transfer_queue,
    );

    g_swap_chain = try swap_chain.create(
        g_allocator,
        g_surface,
        g_framebuffer_width,
        g_framebuffer_height,
    );
    errdefer swap_chain.destroy(&g_swap_chain);

    g_main_render_pass = try render_pass.create(g_swap_chain.format);
    errdefer render_pass.destroy(g_main_render_pass);

    try swap_chain.createFrameBuffers(&g_swap_chain, g_main_render_pass);

    g_graphics_command_pool = try command_pool.create(device.queue_family_indices.graphics_family.?);
    errdefer command_pool.destroy(g_graphics_command_pool);

    g_transfer_command_pool = try command_pool.create(device.queue_family_indices.transfer_family.?);
    errdefer command_pool.destroy(g_transfer_command_pool);

    g_command_buffers = try command_buffers.create(
        g_graphics_command_pool,
        MaxFramesInFlight,
    );
    errdefer command_buffers.destroy(&g_command_buffers);

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
        try device.createSemaphore(
            &semaphore_create_info,
            &g_image_available_semaphores[i],
        );

        try device.createSemaphore(
            &semaphore_create_info,
            &g_render_finished_semaphores[i],
        );

        try device.createFence(
            &fence_create_info,
            &g_in_flight_fences[i],
        );
    }

    g_pipelines = .init(g_allocator);

    try uniform_registry.init(g_allocator);
    errdefer uniform_registry.deinit();

    const pool_size = std.mem.zeroInit(
        c.VkDescriptorPoolSize,
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 128, // TODO: this can be calculated in advance knowing our max resources (see bgfx as example)
        },
    );

    const pool_info = std.mem.zeroInit(
        c.VkDescriptorPoolCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = MaxDescriptorSets * MaxFramesInFlight,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
            .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        },
    );

    try device.createDescriptorPool(&pool_info, &g_descriptor_pool);
    errdefer device.destroyDescriptorPool(g_descriptor_pool);

    vertex_buffers.init();
    index_buffers.init();
    programs.init();
    shaders.init();
    textures.init();
}

pub fn deinit() void {
    log.debug("Deinitializing Vulkan renderer", .{});

    device.deviceWaitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    destroyPendingResources();

    vertex_buffers.deinit();
    index_buffers.deinit();
    programs.deinit();
    shaders.deinit();
    textures.deinit();

    device.destroyDescriptorPool(g_descriptor_pool);

    uniform_registry.deinit();

    for (0..MaxFramesInFlight) |i| {
        device.destroySemaphore(g_image_available_semaphores[i]);
        device.destroySemaphore(g_render_finished_semaphores[i]);
        device.destroyFence(g_in_flight_fences[i]);
    }

    var iterator = g_pipelines.valueIterator();
    while (iterator.next()) |pipeline_value| {
        pipeline.destroy(pipeline_value.*);
    }
    g_pipelines.deinit();

    command_buffers.destroy(&g_command_buffers);
    command_pool.destroy(g_graphics_command_pool);
    command_pool.destroy(g_transfer_command_pool);

    render_pass.destroy(g_main_render_pass);
    swap_chain.destroy(&g_swap_chain);
    surface.destroy(g_surface);
    device.deinit();

    if (g_debug_messenger) |debug_messenger| {
        instance.destroyDebugUtilsMessengerEXT(debug_messenger);
    }

    instance.deinit();
    library.deinit();
}

pub fn getSwapchainSize() [2]u32 {
    return .{
        g_swap_chain.extent.width,
        g_swap_chain.extent.height,
    };
}

pub fn setFramebufferSize(size: [2]u32) void {
    if (g_framebuffer_width != size[0] or g_framebuffer_height != size[1]) {
        g_framebuffer_width = size[0];
        g_framebuffer_height = size[1];
        g_framebuffer_invalidated = true;
    }
}

pub fn createShader(data: *const gfx.ShaderData) !gfx.ShaderHandle {
    return shaders.create(data);
}

pub fn destroyShader(handle: gfx.ShaderHandle) void {
    shaders.destroy(handle);
}

pub fn createProgram(
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
) !gfx.ProgramHandle {
    return programs.create(
        g_allocator,
        vertex_shader,
        fragment_shader,
        g_descriptor_pool,
    );
}

pub fn destroyProgram(handle: gfx.ProgramHandle) void {
    programs.destroy(handle);
}

pub fn createVertexBuffer(
    data: []const u8,
    layout: gfx.VertexLayout,
) !gfx.VertexBufferHandle {
    return vertex_buffers.create(
        g_transfer_command_pool,
        g_transfer_queue,
        layout,
        data,
    );
}

pub fn destroyVertexBuffer(handle: gfx.VertexBufferHandle) void {
    vertex_buffers.destroy(handle);
}

pub fn createIndexBuffer(
    data: []const u8,
    index_type: gfx.IndexType,
) !gfx.IndexBufferHandle {
    return index_buffers.create(
        g_transfer_command_pool,
        g_transfer_queue,
        data,
        index_type,
    );
}

pub fn destroyIndexBuffer(handle: gfx.IndexBufferHandle) void {
    index_buffers.destroy(handle);
}

pub fn createUniformBuffer(
    name: []const u8,
    size: u32,
) !gfx.UniformHandle {
    const handle = try uniform_registry.createBuffer(name, size);

    log.debug("Created uniform buffer:", .{});
    log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroyUniformBuffer(handle: gfx.UniformHandle) void {
    uniform_registry.destroy(handle);

    log.debug("Destroyed uniform buffer with handle {d}", .{handle});
}

pub fn updateUniformBuffer(
    handle: gfx.UniformHandle,
    data: []const u8,
) !void {
    try uniform_registry.updateBuffer(handle, g_current_frame, data);
}

pub fn createCombinedSampler(name: []const u8) !gfx.UniformHandle {
    const handle = try uniform_registry.createCombinedSampler(name);

    log.debug("Created combined sampler:", .{});
    log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroyCombinedSampler(handle: gfx.UniformHandle) void {
    uniform_registry.destroy(handle);

    log.debug("Destroyed combined sampler with handle {d}", .{handle});
}

pub fn createTexture(reader: std.io.AnyReader) !gfx.TextureHandle {
    return textures.create(
        g_arena_allocator,
        g_transfer_command_pool,
        g_transfer_queue,
        reader,
    );
}

pub fn destroyTexture(handle: gfx.TextureHandle) void {
    return textures.destroy(handle);
}

pub fn beginFrame() !bool {
    try device.waitForFences(
        1,
        &g_in_flight_fences[g_current_frame],
        c.VK_TRUE,
        c.UINT64_MAX,
    );

    if (try device.acquireNextImageKHR(
        g_swap_chain.handle,
        c.UINT64_MAX,
        g_image_available_semaphores[g_current_frame],
        null,
        &g_current_image_index,
    ) == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try recreateSwapChain();
        return false;
    }

    try device.resetFences(1, &g_in_flight_fences[g_current_frame]);

    try g_command_buffers.reset(g_current_frame);
    destroyPendingResources();
    try g_command_buffers.begin(g_current_frame, false);

    g_command_buffers.beginRenderPass(
        g_current_frame,
        g_main_render_pass,
        g_swap_chain.frame_buffers.?[g_current_image_index],
        g_swap_chain.extent,
    );

    return true;
}

pub fn endFrame() !void {
    g_command_buffers.endRenderPass(g_current_frame);
    try g_command_buffers.end(g_current_frame);

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
            .pCommandBuffers = &g_command_buffers.handles[g_current_frame],
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        },
    );

    try device.queueSubmit(
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

    const result = try device.queuePresentKHR(g_present_queue, &present_info);
    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or g_framebuffer_invalidated) {
        g_framebuffer_invalidated = false;
        try recreateSwapChain();
    }

    g_current_frame = (g_current_frame + 1) % MaxFramesInFlight;
}

pub fn setViewport(position: [2]u32, size: [2]u32) void {
    const vk_viewport = std.mem.zeroInit(
        c.VkViewport,
        .{
            .x = @as(f32, @floatFromInt(position[0])),
            .y = @as(f32, @floatFromInt(position[1])),
            .width = @as(f32, @floatFromInt(size[0])),
            .height = @as(f32, @floatFromInt(size[1])),
            .minDepth = 0,
            .maxDepth = 1,
        },
    );
    g_command_buffers.setViewport(g_current_frame, &vk_viewport);
}

pub fn setScissor(position: [2]u32, size: [2]u32) void {
    const vk_scissor = std.mem.zeroInit(
        c.VkRect2D,
        .{
            .offset = c.VkOffset2D{
                .x = @as(i32, @intCast(position[0])),
                .y = @as(i32, @intCast(position[1])),
            },
            .extent = c.VkExtent2D{
                .width = size[0],
                .height = size[1],
            },
        },
    );
    g_command_buffers.setScissor(g_current_frame, &vk_scissor);
}

pub fn bindProgram(program: gfx.ProgramHandle) void {
    g_current_program = program;
}

pub fn bindVertexBuffer(vertex_buffer: gfx.VertexBufferHandle) void {
    g_current_vertex_buffer = vertex_buffer;
}

pub fn bindIndexBuffer(handle: gfx.IndexBufferHandle) void {
    g_current_index_buffer = handle;
}

pub fn bindTexture(texture: gfx.TextureHandle, uniform: gfx.UniformHandle) void {
    uniform_registry.updateCombinedSampler(uniform, texture) catch {
        log.err("Failed to update Vulkan combined sampler", .{});
    };
}

pub fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    std.debug.assert(g_current_program != null);
    std.debug.assert(g_current_vertex_buffer != null);

    const pipeline_value = getPipeline(g_current_program.?, vertex_buffers.getLayout(g_current_vertex_buffer.?)) catch {
        log.err("Failed to bind Vulkan program: {d}", .{g_current_program.?});
        return;
    };
    g_command_buffers.bindPipeline(g_current_frame, pipeline_value);

    var offsets = [_]c.VkDeviceSize{0};
    g_command_buffers.bindVertexBuffer(
        g_current_frame,
        vertex_buffers.getBuffer(g_current_vertex_buffer.?),
        @ptrCast(&offsets),
    );

    programs.pushDescriptorSet(
        g_current_program.?,
        &g_command_buffers,
        g_current_frame,
    ) catch {
        log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    g_command_buffers.draw(
        g_current_frame,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    std.debug.assert(g_current_program != null);
    std.debug.assert(g_current_vertex_buffer != null);
    std.debug.assert(g_current_index_buffer != null);

    const pipeline_value = getPipeline(g_current_program.?, vertex_buffers.getLayout(g_current_vertex_buffer.?)) catch {
        log.err("Failed to bind Vulkan program: {d}", .{g_current_program.?});
        return;
    };
    g_command_buffers.bindPipeline(g_current_frame, pipeline_value);

    var offsets = [_]c.VkDeviceSize{0};
    g_command_buffers.bindVertexBuffer(
        g_current_frame,
        vertex_buffers.getBuffer(g_current_vertex_buffer.?),
        @ptrCast(&offsets),
    );

    programs.pushDescriptorSet(
        g_current_program.?,
        &g_command_buffers,
        g_current_frame,
    ) catch {
        log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    const index_type: c_uint = switch (index_buffers.getIndexType(g_current_index_buffer.?)) {
        gfx.IndexType.u8 => c.VK_INDEX_TYPE_UINT8_EXT,
        gfx.IndexType.u16 => c.VK_INDEX_TYPE_UINT16,
        gfx.IndexType.u32 => c.VK_INDEX_TYPE_UINT32,
    };

    g_command_buffers.bindIndexBuffer(
        g_current_frame,
        index_buffers.getBuffer(g_current_index_buffer.?),
        0,
        index_type,
    );

    g_command_buffers.drawIndexed(
        g_current_frame,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
