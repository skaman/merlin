const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const UniformBufferBinding = struct {
    buffer_handle: gfx.BufferHandle,
    offset: u32,
};

const CombinedSamplerBinding = struct {
    texture_handle: gfx.TextureHandle,
};

const UniformBinding = union(types.DescriptorBindType) {
    uniform_buffer: UniformBufferBinding,
    combined_sampler: CombinedSamplerBinding,
};

const PushConstantBinding = struct {
    shader_stage: c.VkShaderStageFlags,
    offset: u32,
    size: u32,
    data: [*c]const u8,
};

pub const CommandBuffer = struct {
    command_pool: c.VkCommandPool,
    handle: c.VkCommandBuffer,

    current_pipeline_layout: ?gfx.PipelineLayoutHandle = null,
    current_debug_options: gfx.DebugOptions = .{},
    current_render_options: gfx.RenderOptions = .{},
    current_program_handle: ?gfx.ProgramHandle = null,
    current_color_attachment_count: u32 = 0,
    current_color_attachment_images: [vk.pipeline.MaxColorAttachments]c.VkImage = undefined,
    current_color_attachment_formats: [vk.pipeline.MaxColorAttachments]c.VkFormat = undefined,
    current_depth_attachment_image: c.VkImage = null,
    current_depth_attachment_format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    current_vertex_buffer_handle: ?gfx.BufferHandle = null,
    current_vertex_buffer_offset: u32 = 0,
    current_index_buffer_handle: ?gfx.BufferHandle = null,
    current_index_buffer_offset: u32 = 0,
    current_uniform_bindings: std.AutoHashMap(gfx.NameHandle, UniformBinding) = undefined,
    current_push_constants: std.ArrayList(PushConstantBinding) = undefined,

    is_pipeline_valid: bool = false,
    last_vertex_buffer_handle: ?gfx.BufferHandle = null,
    last_vertex_buffer_offset: u32 = 0,
    last_index_buffer_handle: ?gfx.BufferHandle = null,
    last_index_buffer_offset: u32 = 0,

    pub fn reset(self: *CommandBuffer) void {
        self.current_pipeline_layout = null;
        self.current_debug_options = .{};
        self.current_render_options = .{};
        self.current_program_handle = null;
        self.current_color_attachment_count = 0;
        self.current_depth_attachment_image = null;
        self.current_depth_attachment_format = c.VK_FORMAT_UNDEFINED;
        self.current_vertex_buffer_handle = null;
        self.current_vertex_buffer_offset = 0;
        self.current_index_buffer_handle = null;
        self.current_index_buffer_offset = 0;
        self.current_uniform_bindings.clearRetainingCapacity();
        self.current_push_constants.clearRetainingCapacity();

        self.is_pipeline_valid = false;

        self.last_vertex_buffer_handle = null;
        self.last_vertex_buffer_offset = 0;
        self.last_index_buffer_handle = null;
        self.last_index_buffer_offset = 0;
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn gfxLoadOpToVulkanLoadOp(load_op: gfx.AttachmentLoadOp) c.VkAttachmentLoadOp {
    switch (load_op) {
        .clear => return c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .load => return c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .dont_care => return c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    }
}

fn gfxStoreOpToVulkanStoreOp(store_op: gfx.AttachmentStoreOp) c.VkAttachmentStoreOp {
    switch (store_op) {
        .store => return c.VK_ATTACHMENT_STORE_OP_STORE,
        .dont_care => return c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
    }
}

fn handleBindPipeline(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
    pipeline_layout_handle: gfx.PipelineLayoutHandle,
    // render_pass_handle: gfx.RenderPassHandle,
    color_attachment_formats: []const c.VkFormat,
    depth_attachment_format: c.VkFormat,
    debug_options: gfx.DebugOptions,
    render_options: gfx.RenderOptions,
) !void {
    var command_buffer = get(command_buffer_handle);
    if (command_buffer.is_pipeline_valid) return;

    const pipeline = try vk.pipeline.getOrCreate(
        program_handle,
        pipeline_layout_handle,
        debug_options,
        render_options,
        color_attachment_formats,
        depth_attachment_format,
    );
    std.debug.assert(pipeline != null);

    vk.device.cmdBindPipeline(
        command_buffer.handle,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline,
    );

    command_buffer.is_pipeline_valid = true;
}

fn handleBindVertexBuffer(command_buffer_handle: gfx.CommandBufferHandle) !void {
    var command_buffer = get(command_buffer_handle);
    std.debug.assert(command_buffer.current_vertex_buffer_handle != null);

    const vertex_buffer_handle = command_buffer.current_vertex_buffer_handle.?;
    const vertex_buffer_offset = command_buffer.current_vertex_buffer_offset;
    if (command_buffer.last_vertex_buffer_handle == vertex_buffer_handle and
        command_buffer.last_vertex_buffer_offset == vertex_buffer_offset)
    {
        return;
    }

    var offsets = [_]c.VkDeviceSize{vertex_buffer_offset};

    vk.device.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        &vk.buffers.get(vertex_buffer_handle).buffer,
        @ptrCast(&offsets),
    );

    command_buffer.last_vertex_buffer_handle = vertex_buffer_handle;
    command_buffer.last_vertex_buffer_offset = vertex_buffer_offset;
}

fn handleBindIndexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_type: types.IndexType,
) !void {
    var command_buffer = get(command_buffer_handle);
    std.debug.assert(command_buffer.current_index_buffer_handle != null);

    const index_buffer_handle = command_buffer.current_index_buffer_handle.?;
    const index_buffer_offset = command_buffer.current_index_buffer_offset;
    if (command_buffer.last_index_buffer_handle == index_buffer_handle and
        command_buffer.last_index_buffer_offset == index_buffer_offset)
    {
        return;
    }

    vk.device.cmdBindIndexBuffer(
        command_buffer.handle,
        vk.buffers.get(index_buffer_handle).buffer,
        index_buffer_offset,
        switch (index_type) {
            .u8 => c.VK_INDEX_TYPE_UINT8_EXT,
            .u16 => c.VK_INDEX_TYPE_UINT16,
            .u32 => c.VK_INDEX_TYPE_UINT32,
        },
    );

    command_buffer.last_index_buffer_handle = index_buffer_handle;
    command_buffer.last_index_buffer_offset = index_buffer_offset;
}

fn handlePushDescriptorSet(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
) !void {
    var command_buffer = get(command_buffer_handle);
    const program = vk.programs.get(program_handle);
    const pipeline_layout = program.pipeline_layout;
    const layout_count = program.layout_count;
    var write_descriptor_sets = &program.write_descriptor_sets;
    var buffer_infos: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorBufferInfo = undefined;
    var image_infos: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorImageInfo = undefined;

    for (0..layout_count) |binding_index| {
        const uniform_name_handle = program.uniform_name_handles[binding_index];
        const descriptor_type = program.descriptor_types[binding_index];
        const uniform_binding = command_buffer.current_uniform_bindings.get(
            uniform_name_handle,
        ) orelse {
            vk.log.err("Failed to find uniform binding for handle", .{});
            return error.UniformBindingNotFound;
        };

        switch (descriptor_type) {
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                std.debug.assert(uniform_binding == .uniform_buffer);
                const buffer = vk.buffers.get(
                    uniform_binding.uniform_buffer.buffer_handle,
                ).buffer;
                const uniform_size = program.uniform_sizes[binding_index];
                buffer_infos[binding_index] = .{
                    .buffer = buffer,
                    .offset = uniform_binding.uniform_buffer.offset,
                    .range = uniform_size,
                };
                write_descriptor_sets[binding_index].pBufferInfo = &buffer_infos[binding_index];
            },
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => {
                std.debug.assert(uniform_binding == .combined_sampler);
                const texture_handle = uniform_binding.combined_sampler.texture_handle;
                const texture = vk.textures.get(texture_handle);
                image_infos[binding_index] = .{
                    .imageLayout = texture.image_layout,
                    .imageView = texture.image_view,
                    .sampler = texture.sampler,
                };
                write_descriptor_sets[binding_index].pImageInfo = &image_infos[binding_index];
            },
            else => {
                vk.log.err(
                    "Unsupported descriptor type: {s}",
                    .{c.string_VkDescriptorType(descriptor_type)},
                );
                return error.UnsupportedDescriptorType;
            },
        }
    }

    vk.device.cmdPushDescriptorSet(
        command_buffer.handle,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline_layout,
        0,
        layout_count,
        write_descriptor_sets,
    );
}

fn handlePushConstants(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
) !void {
    var command_buffer = get(command_buffer_handle);
    const program = vk.programs.get(program_handle);
    const pipeline_layout = program.pipeline_layout;
    const push_constants = command_buffer.current_push_constants.items;

    for (push_constants) |push_constant| {
        vk.device.cmdPushConstants(
            command_buffer.handle,
            pipeline_layout,
            push_constant.shader_stage,
            push_constant.offset,
            push_constant.size,
            push_constant.data,
        );
    }

    command_buffer.current_push_constants.clearRetainingCapacity();
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {}

pub fn deinit() void {}

pub fn create(command_pool: c.VkCommandPool) !gfx.CommandBufferHandle {
    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    var command_buffer: c.VkCommandBuffer = undefined;
    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );
    errdefer vk.device.freeCommandBuffers(
        command_pool,
        1,
        &command_buffer,
    );
    std.debug.assert(command_buffer != null);

    const command_buffer_ptr = try vk.gpa.create(CommandBuffer);
    errdefer vk.gpa.destroy(command_buffer_ptr);

    command_buffer_ptr.* = .{
        .command_pool = command_pool,
        .handle = command_buffer,
        .current_uniform_bindings = .init(vk.gpa),
        .current_push_constants = std.ArrayList(PushConstantBinding).init(vk.gpa),
    };

    vk.log.debug("Created command buffer", .{});

    return .{ .handle = @ptrCast(command_buffer_ptr) };
}

pub fn destroy(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.deinit();
    command_buffer.current_push_constants.deinit();
    vk.device.freeCommandBuffers(
        command_buffer.command_pool,
        1,
        &command_buffer.handle,
    );
    vk.gpa.destroy(command_buffer);

    vk.log.debug("Destroyed command buffer", .{});
}

pub fn beginSingleTimeCommands(command_pool: c.VkCommandPool) !c.VkCommandBuffer {
    std.debug.assert(command_pool != null);

    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    var command_buffer: c.VkCommandBuffer = undefined;
    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );
    std.debug.assert(command_buffer != null);

    const begin_info = std.mem.zeroInit(
        c.VkCommandBufferBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        },
    );

    try vk.device.beginCommandBuffer(command_buffer, &begin_info);

    return command_buffer;
}

pub fn endSingleTimeCommands(
    command_pool: c.VkCommandPool,
    command_buffer: c.VkCommandBuffer,
    queue: c.VkQueue,
) void {
    std.debug.assert(command_pool != null);
    std.debug.assert(command_buffer != null);
    std.debug.assert(queue != null);

    defer vk.device.freeCommandBuffers(
        command_pool,
        1,
        &command_buffer,
    );

    vk.device.endCommandBuffer(command_buffer) catch {
        vk.log.err("Failed to record command buffer", .{});
        return;
    };

    const submit_info = std.mem.zeroInit(
        c.VkSubmitInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        },
    );

    vk.device.queueSubmit(
        queue,
        1,
        &submit_info,
        null,
    ) catch {
        vk.log.err("Failed to submit command buffer", .{});
        return;
    };

    vk.device.queueWaitIdle(queue) catch {
        vk.log.err("Failed to wait for queue to idle", .{});
        return;
    };
}

pub inline fn get(handle: gfx.CommandBufferHandle) *CommandBuffer {
    return @ptrCast(@alignCast(handle.handle));
}

pub fn reset(command_buffer_handle: gfx.CommandBufferHandle) !void {
    const command_buffer = get(command_buffer_handle);

    try vk.device.resetCommandBuffer(command_buffer.handle, 0);
    command_buffer.reset();
}

pub fn begin(command_buffer_handle: gfx.CommandBufferHandle) !void {
    const command_buffer = get(command_buffer_handle);
    const begin_info = std.mem.zeroInit(
        c.VkCommandBufferBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        },
    );

    try vk.device.beginCommandBuffer(
        command_buffer.handle,
        &begin_info,
    );
}

pub fn end(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = get(handle);
    try vk.device.endCommandBuffer(command_buffer.handle);
}

pub fn beginRenderPass(
    command_buffer_handle: gfx.CommandBufferHandle,
    extent: c.VkExtent2D,
    options: gfx.RenderPassOptions,
) !void {
    std.debug.assert(extent.width > 0 and extent.height > 0);
    std.debug.assert(options.color_attachments.len > 0);
    std.debug.assert(options.color_attachments.len <= vk.pipeline.MaxColorAttachments);

    const command_buffer = get(command_buffer_handle);

    const color_attachments = try vk.arena.alloc(
        c.VkRenderingAttachmentInfoKHR,
        options.color_attachments.len,
    );

    for (options.color_attachments, 0..) |color_attachment, i| {
        const image: *const vk.images.Image = @ptrCast(@alignCast(color_attachment.image.handle));
        const image_view: c.VkImageView = @ptrCast(@alignCast(color_attachment.image_view.handle));

        const barrier = std.mem.zeroInit(c.VkImageMemoryBarrier, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = image.image,
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });

        vk.device.cmdPipelineBarrier(
            command_buffer.handle,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );

        color_attachments[i] = std.mem.zeroInit(
            c.VkRenderingAttachmentInfoKHR,
            .{
                .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
                .imageView = image_view,
                .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                .resolveMode = c.VK_RESOLVE_MODE_NONE,
                .loadOp = gfxLoadOpToVulkanLoadOp(color_attachment.load_op),
                .storeOp = gfxStoreOpToVulkanStoreOp(color_attachment.store_op),
                .clearValue = c.VkClearValue{
                    .color = .{
                        .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
                    },
                },
            },
        );
    }

    var begin_info = std.mem.zeroInit(
        c.VkRenderingInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = extent,
            },
            .layerCount = 1,
            .colorAttachmentCount = @as(u32, @intCast(options.color_attachments.len)),
            .pColorAttachments = color_attachments.ptr,
        },
    );

    if (options.depth_attachment) |attachment| {
        const image: *const vk.images.Image = @ptrCast(@alignCast(attachment.image.handle));
        const image_view: c.VkImageView = @ptrCast(@alignCast(attachment.image_view.handle));

        const barrier = std.mem.zeroInit(c.VkImageMemoryBarrier, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .srcAccessMask = 0,
            .dstAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT |
                c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = image.image,
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });

        vk.device.cmdPipelineBarrier(
            command_buffer.handle,
            c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT |
                c.VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );
        const depth_attachment = std.mem.zeroInit(
            c.VkRenderingAttachmentInfoKHR,
            .{
                .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
                .imageView = image_view,
                .imageLayout = c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                .resolveMode = c.VK_RESOLVE_MODE_NONE,
                .loadOp = gfxLoadOpToVulkanLoadOp(attachment.load_op),
                .storeOp = gfxStoreOpToVulkanStoreOp(attachment.store_op),
                .clearValue = c.VkClearValue{
                    .depthStencil = .{
                        .depth = 1.0,
                        .stencil = 0,
                    },
                },
            },
        );

        begin_info.pDepthAttachment = &depth_attachment;
    }

    vk.device.cmdBeginRenderingKHR(
        command_buffer.handle,
        &begin_info,
    );

    for (options.color_attachments, 0..) |color_attachment, i| {
        const image: *const vk.images.Image = @ptrCast(@alignCast(color_attachment.image.handle));
        command_buffer.current_color_attachment_formats[i] = vk.vulkanFormatFromGfxImageFormat(color_attachment.format);
        command_buffer.current_color_attachment_images[i] = image.image;
    }
    command_buffer.current_color_attachment_count = @intCast(options.color_attachments.len);

    if (options.depth_attachment) |depth_attachment| {
        const image: *const vk.images.Image = @ptrCast(@alignCast(depth_attachment.image.handle));
        command_buffer.current_depth_attachment_format = vk.vulkanFormatFromGfxImageFormat(depth_attachment.format);
        command_buffer.current_depth_attachment_image = image.image;
    } else {
        command_buffer.current_depth_attachment_format = c.VK_FORMAT_UNDEFINED;
        command_buffer.current_depth_attachment_image = null;
    }
    command_buffer.is_pipeline_valid = false;
}

pub fn endRenderPass(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdEndRenderingKHR(command_buffer.handle);

    for (0..command_buffer.current_color_attachment_count) |i| {
        const image = command_buffer.current_color_attachment_images[i];

        const barrier = std.mem.zeroInit(c.VkImageMemoryBarrier, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dstAccessMask = c.VK_ACCESS_MEMORY_READ_BIT,
            .oldLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        });

        vk.device.cmdPipelineBarrier(
            command_buffer.handle,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            &barrier,
        );
    }
}

pub fn setViewport(
    command_buffer_handle: gfx.CommandBufferHandle,
    viewport: *const c.VkViewport,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdSetViewport(
        command_buffer.handle,
        0,
        1,
        viewport,
    );
}

pub fn setScissor(
    command_buffer_handle: gfx.CommandBufferHandle,
    scissor: *const c.VkRect2D,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdSetScissor(
        command_buffer.handle,
        0,
        1,
        scissor,
    );
}

pub fn setDebug(
    command_buffer_handle: gfx.CommandBufferHandle,
    debug_options: gfx.DebugOptions,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_debug_options = debug_options;
    command_buffer.is_pipeline_valid = false;
}

pub fn setRender(
    command_buffer_handle: gfx.CommandBufferHandle,
    render_options: gfx.RenderOptions,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_render_options = render_options;
    command_buffer.is_pipeline_valid = false;
}

pub fn bindPipelineLayout(
    command_buffer_handle: gfx.CommandBufferHandle,
    pipeline_layout: gfx.PipelineLayoutHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_pipeline_layout = pipeline_layout;
    command_buffer.is_pipeline_valid = false;
}

pub fn bindProgram(
    command_buffer_handle: gfx.CommandBufferHandle,
    program: gfx.ProgramHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_program_handle = program;
    command_buffer.is_pipeline_valid = false;
}

pub fn bindVertexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    vertex_buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_vertex_buffer_handle = vertex_buffer;
    command_buffer.current_vertex_buffer_offset = offset;
}

pub fn bindIndexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_index_buffer_handle = index_buffer;
    command_buffer.current_index_buffer_offset = offset;
}

pub fn bindUniformBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    name: gfx.NameHandle,
    buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.put(name, .{
        .uniform_buffer = .{
            .buffer_handle = buffer,
            .offset = offset,
        },
    }) catch {
        vk.log.err("Failed to bind uniform buffer", .{});
        return;
    };
}

pub fn bindCombinedSampler(
    command_buffer_handle: gfx.CommandBufferHandle,
    name: gfx.NameHandle,
    texture: gfx.TextureHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.put(name, .{
        .combined_sampler = .{
            .texture_handle = texture,
        },
    }) catch {
        vk.log.err("Failed to bind combined sampler", .{});
        return;
    };
}

pub fn pushConstants(
    command_buffer_handle: gfx.CommandBufferHandle,
    shader_stage: types.ShaderType,
    offset: u32,
    size: u32,
    data: *const u8,
) void {
    const command_buffer = get(command_buffer_handle);
    const push_constant = PushConstantBinding{
        .shader_stage = switch (shader_stage) {
            .vertex => c.VK_SHADER_STAGE_VERTEX_BIT,
            .fragment => c.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .offset = offset,
        .size = size,
        .data = data,
    };
    command_buffer.current_push_constants.append(push_constant) catch {
        vk.log.err("Failed to push constants", .{});
        return;
    };
}

pub fn draw(
    command_buffer_handle: gfx.CommandBufferHandle,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    const current_layout = command_buffer.current_pipeline_layout;
    const current_program = command_buffer.current_program_handle;
    const current_color_attachment_count = command_buffer.current_color_attachment_count;
    const current_color_attachment_formats = command_buffer.current_color_attachment_formats;
    const current_depth_attachment_format = command_buffer.current_depth_attachment_format;
    const current_debug_options = command_buffer.current_debug_options;
    const current_render_options = command_buffer.current_render_options;

    handleBindPipeline(
        command_buffer_handle,
        current_program.?,
        current_layout.?,
        current_color_attachment_formats[0..current_color_attachment_count],
        current_depth_attachment_format,
        current_debug_options,
        current_render_options,
    ) catch {
        vk.log.err("Failed to bind Vulkan program", .{});
        return;
    };

    handleBindVertexBuffer(command_buffer_handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    handlePushConstants(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan push constants", .{});
        return;
    };

    vk.device.cmdDraw(
        command_buffer.handle,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
    index_type: types.IndexType,
) void {
    const command_buffer = get(command_buffer_handle);
    const current_layout = command_buffer.current_pipeline_layout;
    const current_program = command_buffer.current_program_handle;
    const current_color_attachment_count = command_buffer.current_color_attachment_count;
    const current_color_attachment_formats = command_buffer.current_color_attachment_formats;
    const current_depth_attachment_format = command_buffer.current_depth_attachment_format;
    const current_debug_options = command_buffer.current_debug_options;
    const current_render_options = command_buffer.current_render_options;

    handleBindPipeline(
        command_buffer_handle,
        current_program.?,
        current_layout.?,
        current_color_attachment_formats[0..current_color_attachment_count],
        current_depth_attachment_format,
        current_debug_options,
        current_render_options,
    ) catch {
        vk.log.err("Failed to bind Vulkan program", .{});
        return;
    };

    handleBindVertexBuffer(command_buffer_handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    handleBindIndexBuffer(command_buffer_handle, index_type) catch {
        vk.log.err("Failed to bind Vulkan index buffer", .{});
        return;
    };

    handlePushConstants(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan push constants", .{});
        return;
    };

    vk.device.cmdDrawIndexed(
        command_buffer.handle,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}

pub fn beginDebugLabel(
    command_buffer_handle: gfx.CommandBufferHandle,
    label_name: []const u8,
    color: [4]f32,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.debug.beginCommandBufferLabel(
        command_buffer.handle,
        label_name,
        color,
    );
}

pub fn endDebugLabel(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    vk.debug.endCommandBufferLabel(command_buffer.handle);
}

pub fn insertDebugLabel(
    command_buffer_handle: gfx.CommandBufferHandle,
    label_name: []const u8,
    color: [4]f32,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.debug.insertCommandBufferLabel(
        command_buffer.handle,
        label_name,
        color,
    );
}
