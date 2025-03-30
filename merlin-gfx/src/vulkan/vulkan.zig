const std = @import("std");
const builtin = @import("builtin");

const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
pub const buffer = @import("buffer.zig");
pub const command_buffers = @import("command_buffers.zig");
pub const command_pool = @import("command_pool.zig");
pub const depth_image = @import("depth_image.zig");
pub const descriptor_registry = @import("descriptor_registry.zig");
pub const device = @import("device.zig");
pub const image = @import("image.zig");
pub const index_buffers = @import("index_buffers.zig");
pub const instance = @import("instance.zig");
pub const library = @import("library.zig");
pub const pipeline = @import("pipeline.zig");
pub const pipeline_layouts = @import("pipeline_layouts.zig");
pub const programs = @import("programs.zig");
pub const render_pass = @import("render_pass.zig");
pub const shaders = @import("shaders.zig");
pub const surface = @import("surface.zig");
pub const swap_chain = @import("swap_chain.zig");
pub const textures = @import("textures.zig");
pub const uniform_buffers = @import("uniform_buffers.zig");
pub const vertex_buffers = @import("vertex_buffers.zig");

pub const log = std.log.scoped(.gfx_vk);

pub const MaxFramesInFlight = 2;
pub const MaxDescriptorSets = 1024;

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var graphics_queue: c.VkQueue = undefined;
var present_queue: c.VkQueue = undefined;
var transfer_queue: c.VkQueue = undefined;

var main_surface: c.VkSurfaceKHR = undefined;
var main_swap_chain: swap_chain.SwapChain = undefined;
pub var main_render_pass: c.VkRenderPass = undefined; // TODO: this should not be public
var main_depth_image: depth_image.DepthImage = undefined;
var main_command_buffers: [MaxFramesInFlight]gfx.CommandBufferHandle = undefined;
var main_descriptor_pool: c.VkDescriptorPool = undefined;

var graphics_command_pool: c.VkCommandPool = undefined;
var transfer_command_pool: c.VkCommandPool = undefined;

var debug_messenger: ?c.VkDebugUtilsMessengerEXT = null;

var image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var in_flight_fences: [MaxFramesInFlight]c.VkFence = undefined;

var current_image_index: u32 = 0;
var current_frame_in_flight: u32 = 0;

var framebuffer_invalidated: bool = false;

// *********************************************************************************************
// Private API
// *********************************************************************************************

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

    var debug_utils_messenger: c.VkDebugUtilsMessengerEXT = undefined;
    try instance.createDebugUtilsMessengerEXT(
        &create_info,
        &debug_utils_messenger,
    );
    return debug_utils_messenger;
}

fn destroyPendingResources() void {
    vertex_buffers.destroyPendingResources();
    index_buffers.destroyPendingResources();
    uniform_buffers.destroyPendingResources();
    programs.destroyPendingResources();
    shaders.destroyPendingResources();
    textures.destroyPendingResources();
}

fn recreateSwapChain() !void {
    const framebuffer_size = platform.getDefaultWindowFramebufferSize();
    const framebuffer_width = framebuffer_size[0];
    const framebuffer_height = framebuffer_size[1];

    if (framebuffer_width == 0 or framebuffer_height == 0) {
        framebuffer_invalidated = true;
        return;
    }

    try device.deviceWaitIdle();

    depth_image.destroy(main_depth_image);
    swap_chain.destroy(&main_swap_chain);

    main_swap_chain = try swap_chain.create(
        main_surface,
        framebuffer_width,
        framebuffer_height,
    );
    errdefer swap_chain.destroy(&main_swap_chain);

    main_depth_image = try depth_image.create(
        framebuffer_width,
        framebuffer_height,
    );
    errdefer depth_image.destroy(main_depth_image);

    try swap_chain.createFrameBuffers(
        &main_swap_chain,
        main_render_pass,
        main_depth_image.view,
    );
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

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

pub fn findMemoryTypeIndex(
    memory_type_bits: u32,
    property_flags: c.VkMemoryPropertyFlags,
) !u32 {
    var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    instance.getPhysicalDeviceMemoryProperties(
        device.physical_device,
        &memory_properties,
    );

    for (0..memory_properties.memoryTypeCount) |index| {
        if (memory_type_bits & (@as(u32, 1) << @as(u5, @intCast(index))) != 0 and
            memory_properties.memoryTypes[index].propertyFlags & property_flags == property_flags)
        {
            return @intCast(index);
        }
    }

    log.err("Failed to find suitable memory type", .{});

    return error.MemoryTypeNotFound;
}

// *********************************************************************************************
// Public Renderer API
// *********************************************************************************************

pub fn init(
    allocator: std.mem.Allocator,
    options: *const gfx.Options,
) !void {
    log.debug("Initializing Vulkan renderer", .{});

    gpa = allocator;

    arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena_impl.deinit();
    arena = arena_impl.allocator();

    try library.init();
    errdefer library.deinit();

    try instance.init(options);
    errdefer instance.deinit();

    debug_messenger = try setupDebugMessenger(options);

    main_surface = try surface.create();
    errdefer surface.destroy(main_surface);

    try device.init(options, main_surface);
    errdefer device.deinit();

    device.getDeviceQueue(
        device.queue_family_indices.graphics_family.?,
        0,
        &graphics_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.present_family.?,
        0,
        &present_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.transfer_family.?,
        0,
        &transfer_queue,
    );

    const framebuffer_size = platform.getDefaultWindowFramebufferSize();
    const framebuffer_width = framebuffer_size[0];
    const framebuffer_height = framebuffer_size[1];

    main_swap_chain = try swap_chain.create(
        main_surface,
        framebuffer_width,
        framebuffer_height,
    );
    errdefer swap_chain.destroy(&main_swap_chain);

    main_render_pass = try render_pass.create(main_swap_chain.format);
    errdefer render_pass.destroy(main_render_pass);

    main_depth_image = try depth_image.create(
        framebuffer_width,
        framebuffer_height,
    );
    errdefer depth_image.destroy(main_depth_image);

    try swap_chain.createFrameBuffers(
        &main_swap_chain,
        main_render_pass,
        main_depth_image.view,
    );

    graphics_command_pool = try command_pool.create(device.queue_family_indices.graphics_family.?);
    errdefer command_pool.destroy(graphics_command_pool);

    transfer_command_pool = try command_pool.create(device.queue_family_indices.transfer_family.?);
    errdefer command_pool.destroy(transfer_command_pool);

    command_buffers.init();
    errdefer command_buffers.deinit();

    var created_command_buffers: u32 = 0;
    errdefer {
        for (0..created_command_buffers) |i| {
            command_buffers.destroy(main_command_buffers[i]);
        }
    }
    for (0..MaxFramesInFlight) |i| {
        main_command_buffers[i] = try command_buffers.create(graphics_command_pool);
        created_command_buffers += 1;
    }

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

    try descriptor_registry.init();
    errdefer descriptor_registry.deinit();

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

    try device.createDescriptorPool(&pool_info, &main_descriptor_pool);
    errdefer device.destroyDescriptorPool(main_descriptor_pool);

    pipeline_layouts.init();
    pipeline.init();
    vertex_buffers.init();
    index_buffers.init();
    uniform_buffers.init();
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

    textures.deinit();
    shaders.deinit();
    programs.deinit();
    uniform_buffers.deinit();
    index_buffers.deinit();
    vertex_buffers.deinit();
    pipeline.deinit();
    pipeline_layouts.deinit();

    device.destroyDescriptorPool(main_descriptor_pool);

    descriptor_registry.deinit();

    for (0..MaxFramesInFlight) |i| {
        device.destroySemaphore(image_available_semaphores[i]);
        device.destroySemaphore(render_finished_semaphores[i]);
        device.destroyFence(in_flight_fences[i]);
    }

    for (0..MaxFramesInFlight) |i| {
        command_buffers.destroy(main_command_buffers[i]);
    }
    command_buffers.deinit();

    command_pool.destroy(graphics_command_pool);
    command_pool.destroy(transfer_command_pool);

    render_pass.destroy(main_render_pass);
    depth_image.destroy(main_depth_image);
    swap_chain.destroy(&main_swap_chain);
    surface.destroy(main_surface);
    device.deinit();

    if (debug_messenger) |debug_messenger_value| {
        instance.destroyDebugUtilsMessengerEXT(debug_messenger_value);
    }

    instance.deinit();
    library.deinit();

    arena_impl.deinit();
}

pub fn swapchainSize() [2]u32 {
    return .{
        main_swap_chain.extent.width,
        main_swap_chain.extent.height,
    };
}

pub fn maxFramesInFlight() u32 {
    return MaxFramesInFlight;
}

pub fn currentFrameInFlight() u32 {
    return current_frame_in_flight;
}

pub fn createShader(loader: utils.loaders.ShaderLoader) !gfx.ShaderHandle {
    return shaders.create(loader);
}

pub fn destroyShader(handle: gfx.ShaderHandle) void {
    shaders.destroy(handle);
}

pub fn createProgram(
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
) !gfx.ProgramHandle {
    return programs.create(
        vertex_shader,
        fragment_shader,
        main_descriptor_pool,
    );
}

pub fn destroyProgram(handle: gfx.ProgramHandle) void {
    programs.destroy(handle);
}

pub fn createVertexBuffer(
    loader: utils.loaders.VertexBufferLoader,
) !gfx.VertexBufferHandle {
    return vertex_buffers.create(
        transfer_command_pool,
        transfer_queue,
        loader,
    );
}

pub fn destroyVertexBuffer(handle: gfx.VertexBufferHandle) void {
    vertex_buffers.destroy(handle);
}

pub fn createIndexBuffer(
    loader: utils.loaders.IndexBufferLoader,
) !gfx.IndexBufferHandle {
    return index_buffers.create(
        transfer_command_pool,
        transfer_queue,
        loader,
    );
}

pub fn destroyIndexBuffer(handle: gfx.IndexBufferHandle) void {
    index_buffers.destroy(handle);
}

pub fn createUniformBuffer(size: u32) !gfx.UniformBufferHandle {
    return uniform_buffers.create(size);
}

pub fn destroyUniformBuffer(handle: gfx.UniformBufferHandle) void {
    uniform_buffers.destroy(handle);
}

pub fn updateUniformBuffer(handle: gfx.UniformBufferHandle, data: []const u8, offset: u32) void {
    uniform_buffers.update(handle, data, offset);
}

pub fn createTexture(loader: utils.loaders.TextureLoader) !gfx.TextureHandle {
    return textures.create(
        transfer_command_pool,
        transfer_queue,
        loader,
    );
}

pub fn destroyTexture(handle: gfx.TextureHandle) void {
    return textures.destroy(handle);
}

pub fn registerUniformName(name: []const u8) !gfx.UniformHandle {
    return descriptor_registry.registerName(name);
}

pub fn beginFrame() !bool {
    try device.waitForFences(
        1,
        &in_flight_fences[current_frame_in_flight],
        c.VK_TRUE,
        c.UINT64_MAX,
    );

    if (try device.acquireNextImageKHR(
        main_swap_chain.handle,
        c.UINT64_MAX,
        image_available_semaphores[current_frame_in_flight],
        null,
        &current_image_index,
    ) == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try recreateSwapChain();
        return false;
    }

    try device.resetFences(1, &in_flight_fences[current_frame_in_flight]);

    try command_buffers.reset(main_command_buffers[current_frame_in_flight]);
    destroyPendingResources();
    try command_buffers.begin(main_command_buffers[current_frame_in_flight]);

    try command_buffers.beginRenderPass(
        main_command_buffers[current_frame_in_flight],
        main_render_pass,
        main_swap_chain.frame_buffers.?[current_image_index],
        main_swap_chain.extent,
    );

    return true;
}

pub fn endFrame() !void {
    command_buffers.endRenderPass(main_command_buffers[current_frame_in_flight]);
    try command_buffers.end(main_command_buffers[current_frame_in_flight]);

    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const wait_semaphores = [_]c.VkSemaphore{image_available_semaphores[current_frame_in_flight]};
    const signal_semaphores = [_]c.VkSemaphore{render_finished_semaphores[current_frame_in_flight]};
    const submit_info = std.mem.zeroInit(
        c.VkSubmitInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffers.commandBuffer(main_command_buffers[current_frame_in_flight]),
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        },
    );

    try device.queueSubmit(
        graphics_queue,
        1,
        &submit_info,
        in_flight_fences[current_frame_in_flight],
    );

    const present_info = std.mem.zeroInit(
        c.VkPresentInfoKHR,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &main_swap_chain.handle,
            .pImageIndices = &current_image_index,
        },
    );

    const framebuffer_size = platform.getDefaultWindowFramebufferSize();
    if (main_swap_chain.extent.width != framebuffer_size[0] or main_swap_chain.extent.height != framebuffer_size[1]) {
        framebuffer_invalidated = true;
    }

    const result = try device.queuePresentKHR(present_queue, &present_info);
    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or framebuffer_invalidated) {
        framebuffer_invalidated = false;
        try recreateSwapChain();
    }

    current_frame_in_flight = (current_frame_in_flight + 1) % MaxFramesInFlight;

    _ = arena_impl.reset(.retain_capacity);
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

    command_buffers.setViewport(
        main_command_buffers[current_frame_in_flight],
        &vk_viewport,
    );
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
    command_buffers.setScissor(
        main_command_buffers[current_frame_in_flight],
        &vk_scissor,
    );
}

pub fn bindProgram(program: gfx.ProgramHandle) void {
    command_buffers.bindProgram(
        main_command_buffers[current_frame_in_flight],
        program,
    );
}

pub fn bindVertexBuffer(vertex_buffer: gfx.VertexBufferHandle) void {
    command_buffers.bindVertexBuffer(
        main_command_buffers[current_frame_in_flight],
        vertex_buffer,
    );
}

pub fn bindIndexBuffer(index_buffer: gfx.IndexBufferHandle) void {
    command_buffers.bindIndexBuffer(
        main_command_buffers[current_frame_in_flight],
        index_buffer,
    );
}

pub fn bindUniformBuffer(uniform: gfx.UniformHandle, uniform_buffer: gfx.UniformBufferHandle, offset: u32) void {
    command_buffers.bindUniformBuffer(
        main_command_buffers[current_frame_in_flight],
        uniform,
        uniform_buffer,
        offset,
    );
}

pub fn bindCombinedSampler(uniform: gfx.UniformHandle, texture: gfx.TextureHandle) void {
    command_buffers.bindCombinedSampler(
        main_command_buffers[current_frame_in_flight],
        uniform,
        texture,
    );
}

pub fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    command_buffers.draw(
        main_command_buffers[current_frame_in_flight],
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
    command_buffers.drawIndexed(
        main_command_buffers[current_frame_in_flight],
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
