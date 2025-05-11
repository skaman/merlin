const std = @import("std");
const builtin = @import("builtin");

const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
pub const buffers = @import("buffers.zig");
pub const command_buffers = @import("command_buffers.zig");
pub const command_pool = @import("command_pool.zig");
pub const custom_allocator = @import("custom_allocator.zig");
pub const debug = @import("debug.zig");
pub const device = @import("device.zig");
pub const framebuffers = @import("framebuffers.zig");
pub const image = @import("image.zig");
pub const instance = @import("instance.zig");
pub const library = @import("library.zig");
pub const pipeline = @import("pipeline.zig");
pub const pipeline_layouts = @import("pipeline_layouts.zig");
pub const programs = @import("programs.zig");
pub const render_pass = @import("render_pass.zig");
pub const shaders = @import("shaders.zig");
pub const textures = @import("textures.zig");

pub const log = std.log.scoped(.gfx_vk);

pub const MaxFramesInFlight = 2;
pub const MaxDescriptorSets = 1024;

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var _arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var _graphics_queue: c.VkQueue = undefined;
var _present_queue: c.VkQueue = undefined;
var _transfer_queue: c.VkQueue = undefined;

var _descriptor_pool: c.VkDescriptorPool = undefined;

var _graphics_command_pool: c.VkCommandPool = undefined;
var _transfer_command_pool: c.VkCommandPool = undefined;

var _current_frame_in_flight: u32 = 0;
var _current_framebuffer: *framebuffers.Framebuffer = undefined;

var _surface_format: c.VkSurfaceFormatKHR = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn destroyPendingResources() !void {
    render_pass.destroyPendingResources();
    try framebuffers.destroyPendingResources();
    buffers.destroyPendingResources();
    programs.destroyPendingResources();
    shaders.destroyPendingResources();
    textures.destroyPendingResources();
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

    _arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer _arena_impl.deinit();
    arena = _arena_impl.allocator();

    try library.init();
    errdefer library.deinit();

    try instance.init(options);
    errdefer instance.deinit();

    try debug.init(options);
    errdefer debug.deinit();

    const surface = try framebuffers.createSurface(
        options.window_handle,
    );
    defer framebuffers.destroySurface(surface);

    try device.init(options, surface);
    errdefer device.deinit();

    device.getDeviceQueue(
        device.queue_family_indices.graphics_family.?,
        0,
        &_graphics_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.present_family.?,
        0,
        &_present_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.transfer_family.?,
        0,
        &_transfer_queue,
    );

    _surface_format = try framebuffers.getSurfaceFormat(surface);

    _graphics_command_pool = try command_pool.create(device.queue_family_indices.graphics_family.?);
    errdefer command_pool.destroy(_graphics_command_pool);

    _transfer_command_pool = try command_pool.create(device.queue_family_indices.transfer_family.?);
    errdefer command_pool.destroy(_transfer_command_pool);

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

    try device.createDescriptorPool(&pool_info, &_descriptor_pool);
    errdefer device.destroyDescriptorPool(_descriptor_pool);

    pipeline_layouts.init();
    pipeline.init();
    buffers.init();
    programs.init();
    shaders.init();
    textures.init();
    render_pass.init();
    framebuffers.init();
}

pub fn deinit() void {
    log.debug("Deinitializing Vulkan renderer", .{});

    device.deviceWaitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    destroyPendingResources() catch {
        log.err("Failed to destroy pending resources", .{});
    };

    framebuffers.deinit();
    render_pass.deinit();
    textures.deinit();
    shaders.deinit();
    programs.deinit();
    buffers.deinit();
    pipeline.deinit();
    pipeline_layouts.deinit();

    device.destroyDescriptorPool(_descriptor_pool);

    command_buffers.deinit();

    command_pool.destroy(_graphics_command_pool);
    command_pool.destroy(_transfer_command_pool);

    device.deinit();
    debug.deinit();
    instance.deinit();
    library.deinit();

    _arena_impl.deinit();
}

pub fn swapchainSize(handle: gfx.FramebufferHandle) [2]u32 {
    return framebuffers.swapchainSize(handle);
}

pub fn uniformAlignment() u32 {
    return @intCast(device.properties.limits.minUniformBufferOffsetAlignment);
}

pub fn maxFramesInFlight() u32 {
    return MaxFramesInFlight;
}

pub fn currentFrameInFlight() u32 {
    return _current_frame_in_flight;
}

pub fn createFramebuffer(
    window_handle: platform.WindowHandle,
    render_pass_handle: gfx.RenderPassHandle,
) !gfx.FramebufferHandle {
    return try framebuffers.create(
        window_handle,
        _graphics_command_pool,
        render_pass_handle,
    );
}

pub fn destroyFramebuffer(handle: gfx.FramebufferHandle) void {
    framebuffers.destroy(handle);
}

pub fn createRenderPass() !gfx.RenderPassHandle {
    return render_pass.create(_surface_format.format);
}

pub fn destroyRenderPass(handle: gfx.RenderPassHandle) void {
    render_pass.destroy(handle);
}

pub fn createShader(reader: std.io.AnyReader, options: gfx.ShaderOptions) !gfx.ShaderHandle {
    return shaders.create(reader, options);
}

pub fn destroyShader(handle: gfx.ShaderHandle) void {
    shaders.destroy(handle);
}

pub fn createPipelineLayout(
    vertex_layout: types.VertexLayout,
) !gfx.PipelineLayoutHandle {
    return pipeline_layouts.create(vertex_layout);
}

pub fn destroyPipelineLayout(handle: gfx.PipelineLayoutHandle) void {
    pipeline_layouts.destroy(handle);
}

pub fn createProgram(
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
    options: gfx.ProgramOptions,
) !gfx.ProgramHandle {
    return programs.create(
        vertex_shader,
        fragment_shader,
        _descriptor_pool,
        options,
    );
}

pub fn destroyProgram(handle: gfx.ProgramHandle) void {
    programs.destroy(handle);
}

pub fn createBuffer(
    size: u32,
    usage: gfx.BufferUsage,
    location: gfx.BufferLocation,
    options: gfx.BufferOptions,
) !gfx.BufferHandle {
    return buffers.create(size, usage, location, options);
}

pub fn destroyBuffer(handle: gfx.BufferHandle) void {
    buffers.destroy(handle);
}

pub fn updateBuffer(
    handle: gfx.BufferHandle,
    reader: std.io.AnyReader,
    offset: u32,
    size: u32,
) !void {
    try buffers.update(
        _transfer_command_pool,
        _transfer_queue,
        handle,
        reader,
        offset,
        size,
    );
}

pub fn createTexture(reader: std.io.AnyReader, size: u32, options: gfx.TextureOptions) !gfx.TextureHandle {
    return textures.create(
        _transfer_command_pool,
        _graphics_command_pool,
        _transfer_queue,
        _graphics_queue,
        reader,
        size,
        options,
    );
}

pub fn createTextureFromKTX(reader: std.io.AnyReader, size: u32, options: gfx.TextureKTXOptions) !gfx.TextureHandle {
    return textures.createFromKTX(
        _transfer_command_pool,
        _transfer_queue,
        reader,
        size,
        options,
    );
}

pub fn destroyTexture(handle: gfx.TextureHandle) void {
    return textures.destroy(handle);
}

pub fn beginFrame() !bool {
    //log.debug("Memory usage: {d}", .{custom_allocator.vulkan_memory_usage});

    for (framebuffers.getAll()) |framebuffer| {
        try device.waitForFences(
            1,
            &framebuffer.in_flight_fences[_current_frame_in_flight],
            c.VK_TRUE,
            c.UINT64_MAX,
        );
    }

    try destroyPendingResources();

    var all_acquired = true;
    for (framebuffers.getAll()) |framebuffer| {
        framebuffer.is_image_acquired = false;
        const result = device.acquireNextImageKHR(
            framebuffer.swap_chain,
            c.UINT64_MAX,
            framebuffer.image_available_semaphores[_current_frame_in_flight],
            null,
            &framebuffer.current_image_index,
        ) catch |err| {
            log.err("Failed to acquire next image: {}", .{err});
            all_acquired = false;
            continue;
        };

        if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            log.debug("Swapchain out of date, recreating swapchain", .{});
            try framebuffers.recreateSwapchain(framebuffer);
            all_acquired = false;
        } else {
            framebuffer.is_image_acquired = true;
        }
    }

    for (framebuffers.getAll()) |framebuffer| {
        if (!framebuffer.is_image_acquired) continue;

        try device.resetFences(
            1,
            &framebuffer.in_flight_fences[_current_frame_in_flight],
        );

        try command_buffers.reset(framebuffer.command_buffers[_current_frame_in_flight]);
        try command_buffers.begin(framebuffer.command_buffers[_current_frame_in_flight]);
        framebuffer.is_buffer_recording = true;
    }

    // If we can't acquire an image, we can't start the frame, we call endFrame
    // to clean up stuff that maybe was created.
    if (!all_acquired) {
        try endFrame();
        return false;
    }

    return true;
}

pub fn endFrame() !void {
    defer _ = _arena_impl.reset(.retain_capacity);

    for (framebuffers.getAll()) |framebuffer| {
        if (!framebuffer.is_image_acquired) continue;

        if (framebuffer.is_buffer_recording) {
            try command_buffers.end(framebuffer.command_buffers[_current_frame_in_flight]);
            framebuffer.is_buffer_recording = false;
        }

        const wait_stages =
            [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const wait_semaphores =
            [_]c.VkSemaphore{framebuffer.image_available_semaphores[_current_frame_in_flight]};
        const signal_semaphores =
            [_]c.VkSemaphore{framebuffer.render_finished_semaphores[_current_frame_in_flight]};
        const command_buffer =
            command_buffers.get(framebuffer.command_buffers[_current_frame_in_flight]);
        const submit_info = std.mem.zeroInit(
            c.VkSubmitInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &wait_semaphores,
                .pWaitDstStageMask = &wait_stages,
                .commandBufferCount = 1,
                .pCommandBuffers = &command_buffer.handle,
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = &signal_semaphores,
            },
        );

        try device.queueSubmit(
            _graphics_queue,
            1,
            &submit_info,
            framebuffer.in_flight_fences[_current_frame_in_flight],
        );

        const present_info = std.mem.zeroInit(
            c.VkPresentInfoKHR,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &signal_semaphores,
                .swapchainCount = 1,
                .pSwapchains = &framebuffer.swap_chain,
                .pImageIndices = &framebuffer.current_image_index,
            },
        );

        if (!framebuffer.is_destroying) {
            const framebuffer_size = platform.windowFramebufferSize(framebuffer.window_handle);
            if (framebuffer.extent.width != framebuffer_size[0] or framebuffer.extent.height != framebuffer_size[1]) {
                framebuffer.framebuffer_invalidated = true;
            }
        }

        const result = try device.queuePresentKHR(_present_queue, &present_info);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or framebuffer.framebuffer_invalidated) {
            framebuffer.framebuffer_invalidated = false;
            log.debug("Framebuffer invalidated, recreating swapchain", .{});
            try framebuffers.recreateSwapchain(framebuffer);
        }
    }

    _current_frame_in_flight = (_current_frame_in_flight + 1) % MaxFramesInFlight;
}

pub fn beginRenderPass(framebuffer_handle: gfx.FramebufferHandle, render_pass_handle: gfx.RenderPassHandle) !bool {
    const framebuffer = framebuffers.get(framebuffer_handle);
    if (!framebuffer.is_image_acquired or !framebuffer.is_buffer_recording) {
        return false;
    }

    try command_buffers.beginRenderPass(
        framebuffer.command_buffers[_current_frame_in_flight],
        render_pass_handle,
        framebuffer.framebuffers[framebuffer.current_image_index],
        framebuffer.extent,
    );

    _current_framebuffer = framebuffer;

    return true;
}

pub fn endRenderPass() void {
    command_buffers.endRenderPass(_current_framebuffer.command_buffers[_current_frame_in_flight]);
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
        _current_framebuffer.command_buffers[_current_frame_in_flight],
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
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        &vk_scissor,
    );
}

pub fn setDebug(debug_options: gfx.DebugOptions) void {
    command_buffers.setDebug(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        debug_options,
    );
}

pub fn setRender(render_options: gfx.RenderOptions) void {
    command_buffers.setRender(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        render_options,
    );
}

pub fn bindPipelineLayout(pipeline_layout: gfx.PipelineLayoutHandle) void {
    command_buffers.bindPipelineLayout(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        pipeline_layout,
    );
}

pub fn bindProgram(program: gfx.ProgramHandle) void {
    command_buffers.bindProgram(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        program,
    );
}

pub fn bindVertexBuffer(buffer: gfx.BufferHandle, offset: u32) void {
    command_buffers.bindVertexBuffer(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        buffer,
        offset,
    );
}

pub fn bindIndexBuffer(buffer: gfx.BufferHandle, offset: u32) void {
    command_buffers.bindIndexBuffer(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        buffer,
        offset,
    );
}

pub fn bindUniformBuffer(name: gfx.NameHandle, buffer: gfx.BufferHandle, offset: u32) void {
    command_buffers.bindUniformBuffer(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        name,
        buffer,
        offset,
    );
}

pub fn bindCombinedSampler(name: gfx.NameHandle, texture: gfx.TextureHandle) void {
    command_buffers.bindCombinedSampler(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        name,
        texture,
    );
}

pub fn pushConstants(
    shader_stage: types.ShaderType,
    offset: u32,
    data: []const u8,
) void {
    command_buffers.pushConstants(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        shader_stage,
        offset,
        @intCast(data.len),
        @ptrCast(data.ptr),
    );
}

pub fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    command_buffers.draw(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
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
    index_type: types.IndexType,
) void {
    command_buffers.drawIndexed(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
        index_type,
    );
}

pub fn beginDebugLabel(
    label_name: []const u8,
    color: [4]f32,
) void {
    command_buffers.beginDebugLabel(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        label_name,
        color,
    );
}

pub fn endDebugLabel() void {
    command_buffers.endDebugLabel(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
    );
}

pub fn insertDebugLabel(
    label_name: []const u8,
    color: [4]f32,
) void {
    command_buffers.insertDebugLabel(
        _current_framebuffer.command_buffers[_current_frame_in_flight],
        label_name,
        color,
    );
}
