const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
pub const Buffer = @import("buffer.zig").Buffer;
pub const CommandBuffers = @import("command_buffers.zig").CommandBuffers;
pub const CommandPool = @import("command_pool.zig").CommandPool;
pub const Device = @import("device.zig").Device;
pub const IndexBuffer = @import("index_buffer.zig").IndexBuffer;
pub const Instance = @import("instance.zig").Instance;
pub const Library = @import("library.zig").Library;
pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Program = @import("program.zig").Program;
pub const RenderPass = @import("render_pass.zig").RenderPass;
pub const Shader = @import("shader.zig").Shader;
pub const Surface = @import("surface.zig").Surface;
pub const SwapChain = @import("swap_chain.zig").SwapChain;
pub const SwapChainSupportDetails = @import("swap_chain.zig").SwapChainSupportDetails;
pub const Texture = @import("texture.zig").Texture;
pub const UniformBuffer = @import("uniform_buffer.zig").UniformBuffer;
pub const UniformRegistry = @import("uniform_registry.zig").UniformRegistry;
pub const VertexBuffer = @import("vertex_buffer.zig").VertexBuffer;

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
var g_library: Library = undefined;
var g_instance: *Instance = undefined;
var g_device: *Device = undefined;
var g_graphics_queue: c.VkQueue = undefined;
var g_present_queue: c.VkQueue = undefined;
var g_transfer_queue: c.VkQueue = undefined;
var g_surface: *Surface = undefined;
var g_swap_chain: *SwapChain = undefined;
var g_main_render_pass: *RenderPass = undefined;
var g_graphics_command_pool: *CommandPool = undefined;
var g_transfer_command_pool: *CommandPool = undefined;
var g_command_buffers: *CommandBuffers = undefined;
var g_debug_messenger: ?c.VkDebugUtilsMessengerEXT = null;
var g_uniform_registry: *UniformRegistry = undefined;
var g_descriptor_pool: c.VkDescriptorPool = undefined;

var m_shaders: [gfx.MaxShaderHandles]Shader = undefined;
var g_programs: [gfx.MaxProgramHandles]Program = undefined;
var g_pipelines: std.AutoHashMap(PipelineKey, Pipeline) = undefined;
var g_vertex_buffers: [gfx.MaxVertexBufferHandles]VertexBuffer = undefined;
var g_index_buffers: [gfx.MaxIndexBufferHandles]IndexBuffer = undefined;
var g_uniform_buffers: [gfx.MaxUniformHandles]*UniformRegistry.Entry = undefined;
var g_textures: [gfx.MaxTextureHandles]Texture = undefined;

var g_vertex_buffers_to_destroy: [gfx.MaxProgramHandles]VertexBuffer = undefined;
var g_vertex_buffers_to_destroy_count: u32 = 0;
var g_index_buffers_to_destroy: [gfx.MaxProgramHandles]IndexBuffer = undefined;
var g_index_buffers_to_destroy_count: u32 = 0;
var g_programs_to_destroy: [gfx.MaxProgramHandles]Program = undefined;
var g_programs_to_destroy_count: u32 = 0;
var g_shaders_to_destroy: [gfx.MaxShaderHandles]Shader = undefined;
var g_shaders_to_destroy_count: u32 = 0;
var g_textures_to_destroy: [gfx.MaxTextureHandles]Texture = undefined;
var g_textures_to_destroy_count: u32 = 0;

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

fn setupDebugMessenger(options: *const gfx.Options, instance: *Instance) !?c.VkDebugUtilsMessengerEXT {
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
    for (0..g_vertex_buffers_to_destroy_count) |i| {
        g_vertex_buffers_to_destroy[i].deinit();
    }
    g_vertex_buffers_to_destroy_count = 0;

    for (0..g_index_buffers_to_destroy_count) |i| {
        g_index_buffers_to_destroy[i].deinit();
    }
    g_index_buffers_to_destroy_count = 0;

    for (0..g_programs_to_destroy_count) |i| {
        g_programs_to_destroy[i].deinit();
    }
    g_programs_to_destroy_count = 0;

    for (0..g_shaders_to_destroy_count) |i| {
        g_shaders_to_destroy[i].deinit();
    }
    g_shaders_to_destroy_count = 0;

    for (0..g_textures_to_destroy_count) |i| {
        g_textures_to_destroy[i].deinit();
    }
    g_textures_to_destroy_count = 0;
}

fn recreateSwapChain() !void {
    if (g_framebuffer_width == 0 or g_framebuffer_height == 0) {
        g_framebuffer_invalidated = true;
        return;
    }

    g_device.deviceWaitIdle() catch {
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
        g_framebuffer_width,
        g_framebuffer_height,
    );

    try g_swap_chain.createFrameBuffers(g_main_render_pass);
}

fn getPipeline(
    program: gfx.ProgramHandle,
    layout: *gfx.VertexLayout,
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
        &g_library,
        g_instance,
        &g_options,
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

    g_device.getDeviceQueue(
        g_device.queue_family_indices.transfer_family.?,
        0,
        &g_transfer_queue,
    );

    g_swap_chain = try g_allocator.create(SwapChain);
    errdefer g_allocator.destroy(g_swap_chain);
    g_swap_chain.* = try SwapChain.init(
        g_allocator,
        g_instance,
        g_device,
        g_surface,
        g_framebuffer_width,
        g_framebuffer_height,
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

    g_graphics_command_pool = try g_allocator.create(CommandPool);
    errdefer g_allocator.destroy(g_graphics_command_pool);
    g_graphics_command_pool.* = try CommandPool.init(
        g_device,
        g_device.queue_family_indices.graphics_family.?,
    );
    errdefer g_graphics_command_pool.deinit();

    g_transfer_command_pool = try g_allocator.create(CommandPool);
    errdefer g_allocator.destroy(g_transfer_command_pool);
    g_transfer_command_pool.* = try CommandPool.init(
        g_device,
        g_device.queue_family_indices.transfer_family.?,
    );
    errdefer g_transfer_command_pool.deinit();

    g_command_buffers = try g_allocator.create(CommandBuffers);
    errdefer g_allocator.destroy(g_command_buffers);
    g_command_buffers.* = try CommandBuffers.init(
        g_device,
        g_graphics_command_pool,
        MaxFramesInFlight,
    );
    errdefer g_command_buffers.deinit();

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

    g_uniform_registry = try g_allocator.create(UniformRegistry);
    errdefer g_allocator.destroy(g_uniform_registry);

    g_uniform_registry.* = try UniformRegistry.init(
        g_allocator,
        g_device,
    );
    errdefer g_uniform_registry.deinit();

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

    try g_device.createDescriptorPool(&pool_info, &g_descriptor_pool);
    errdefer g_device.destroyDescriptorPool(g_descriptor_pool);
}

pub fn deinit() void {
    log.debug("Deinitializing Vulkan renderer", .{});

    g_device.deviceWaitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    destroyPendingResources();

    g_device.destroyDescriptorPool(g_descriptor_pool);

    g_uniform_registry.deinit();
    g_allocator.destroy(g_uniform_registry);

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

    g_command_buffers.deinit();
    g_allocator.destroy(g_command_buffers);

    g_graphics_command_pool.deinit();
    g_allocator.destroy(g_graphics_command_pool);

    g_transfer_command_pool.deinit();
    g_allocator.destroy(g_transfer_command_pool);

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

pub fn createShader(
    handle: gfx.ShaderHandle,
    data: *const gfx.ShaderData,
) !void {
    m_shaders[handle] = try Shader.init(g_device, data);

    log.debug("Created {s} shader:", .{switch (data.type) {
        .vertex => "vertex",
        .fragment => "fragment",
    }});
    log.debug("  - Handle: {d}", .{handle});

    for (data.input_attributes) |input_attribute| {
        log.debug("  - Attribute {d}: {}", .{ input_attribute.location, input_attribute.attribute });
    }

    for (data.descriptor_sets) |descriptor_set| {
        log.debug("  - Descriptor set {d}:", .{descriptor_set.set});
        for (descriptor_set.bindings) |binding| {
            log.debug("    Binding {d}: {s} {}", .{ binding.binding, binding.name, binding.type });
        }
    }
}

pub fn destroyShader(
    handle: gfx.ShaderHandle,
) void {
    //m_shaders[handle].deinit();
    g_shaders_to_destroy[g_shaders_to_destroy_count] = m_shaders[handle];
    g_shaders_to_destroy_count += 1;

    log.debug("Destroyed shader with handle {d}", .{handle});
}

pub fn createProgram(
    handle: gfx.ProgramHandle,
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
) !void {
    g_programs[handle] = try Program.init(
        g_allocator,
        g_device,
        &m_shaders[vertex_shader],
        &m_shaders[fragment_shader],
        g_uniform_registry,
        g_descriptor_pool,
    );

    log.debug("Created program:", .{});
    log.debug("  - Handle: {d}", .{handle});
    log.debug("  - Vertex shader handle: {d}", .{vertex_shader});
    log.debug("  - Fragment shader handle: {d}", .{fragment_shader});
}

pub fn destroyProgram(
    handle: gfx.ProgramHandle,
) void {
    //g_programs[handle].deinit();
    g_programs_to_destroy[g_programs_to_destroy_count] = g_programs[handle];
    g_programs_to_destroy_count += 1;
    log.debug("Destroyed program with handle {d}", .{handle});
}

pub fn createVertexBuffer(
    handle: gfx.VertexBufferHandle,
    data: []const u8,
    layout: gfx.VertexLayout,
) !void {
    g_vertex_buffers[handle] = try VertexBuffer.init(
        g_device,
        g_transfer_command_pool,
        g_transfer_queue,
        layout,
        data,
    );

    log.debug("Created vertex buffer:", .{});
    log.debug("  - Handle: {d}", .{handle});
}

pub fn destroyVertexBuffer(
    handle: gfx.VertexBufferHandle,
) void {
    g_vertex_buffers_to_destroy[g_vertex_buffers_to_destroy_count] = g_vertex_buffers[handle];
    g_vertex_buffers_to_destroy_count += 1;
    log.debug("Destroyed vertex buffer with handle {d}", .{handle});
}

pub fn createIndexBuffer(
    handle: gfx.IndexBufferHandle,
    data: []const u8,
    index_type: gfx.IndexType,
) !void {
    g_index_buffers[handle] = try IndexBuffer.init(
        g_device,
        g_transfer_command_pool,
        g_transfer_queue,
        data,
        index_type,
    );

    log.debug("Created index buffer:", .{});
    log.debug("  - Handle: {d}", .{handle});
}

pub fn destroyIndexBuffer(
    handle: gfx.IndexBufferHandle,
) void {
    g_index_buffers_to_destroy[g_index_buffers_to_destroy_count] = g_index_buffers[handle];
    g_index_buffers_to_destroy_count += 1;
    log.debug("Destroyed index buffer with handle {d}", .{handle});
}

pub fn createUniformBuffer(
    handle: gfx.UniformHandle,
    name: []const u8,
    size: u32,
) !void {
    g_uniform_buffers[handle] = try g_uniform_registry.create(name, size);
    log.debug("Created uniform buffer:", .{});
    log.debug("  - Handle: {d}", .{handle});
}

pub fn destroyUniformBuffer(
    handle: gfx.UniformHandle,
) void {
    g_uniform_registry.destroy(g_uniform_buffers[handle].name);
    log.debug("Destroyed uniform buffer with handle {d}", .{handle});
}

pub fn updateUniformBuffer(
    handle: gfx.UniformHandle,
    data: []const u8,
) !void {
    g_uniform_buffers[handle].buffer[g_current_frame].update(data);
}

pub fn createTexture(
    handle: gfx.TextureHandle,
    reader: std.io.AnyReader,
) !void {
    g_textures[handle] = try Texture.init(
        g_arena_allocator,
        g_device,
        g_transfer_command_pool,
        g_transfer_queue,
        reader,
    );

    log.debug("Created texture:", .{});
    log.debug("  - Handle: {d}", .{handle});
}

pub fn destroyTexture(
    handle: gfx.TextureHandle,
) void {
    g_textures_to_destroy[g_textures_to_destroy_count] = g_textures[handle];
    g_textures_to_destroy_count += 1;

    log.debug("Destroyed texture with handle {d}", .{handle});
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

    try g_command_buffers.reset(g_current_frame);
    destroyPendingResources();
    try g_command_buffers.begin(g_current_frame, false);

    g_command_buffers.beginRenderPass(
        g_current_frame,
        g_main_render_pass.handle,
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

pub fn bindIndexBuffer(index_buffer: gfx.IndexBufferHandle) void {
    g_current_index_buffer = index_buffer;
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
    g_command_buffers.bindPipeline(g_current_frame, pipeline.handle);

    var offsets = [_]c.VkDeviceSize{0};
    g_command_buffers.bindVertexBuffer(
        g_current_frame,
        vertex_buffer.buffer.handle,
        @ptrCast(&offsets),
    );

    var program = &g_programs[g_current_program.?];

    g_command_buffers.bindDescriptorSets(
        g_current_frame,
        program.pipeline_layout,
        0,
        1,
        &program.descriptor_sets[g_current_frame],
        0,
        null,
    );

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

    const vertex_buffer = &g_vertex_buffers[g_current_vertex_buffer.?];
    const pipeline = getPipeline(g_current_program.?, &vertex_buffer.layout) catch {
        log.err("Failed to bind Vulkan program: {d}", .{g_current_program.?});
        return;
    };
    g_command_buffers.bindPipeline(g_current_frame, pipeline.handle);

    var offsets = [_]c.VkDeviceSize{0};
    g_command_buffers.bindVertexBuffer(
        g_current_frame,
        vertex_buffer.buffer.handle,
        @ptrCast(&offsets),
    );

    var program = &g_programs[g_current_program.?];

    g_command_buffers.bindDescriptorSets(
        g_current_frame,
        program.pipeline_layout,
        0,
        1,
        &program.descriptor_sets[g_current_frame],
        0,
        null,
    );

    const index_type: c_uint = switch (g_index_buffers[g_current_index_buffer.?].index_type) {
        gfx.IndexType.u8 => c.VK_INDEX_TYPE_UINT8_EXT,
        gfx.IndexType.u16 => c.VK_INDEX_TYPE_UINT16,
        gfx.IndexType.u32 => c.VK_INDEX_TYPE_UINT32,
    };

    g_command_buffers.bindIndexBuffer(
        g_current_frame,
        g_index_buffers[g_current_index_buffer.?].buffer.handle,
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
