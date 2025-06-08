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

pub const CommandBuffer = struct {
    command_pool: c.VkCommandPool,
    handle: c.VkCommandBuffer,

    current_program_handle: gfx.ProgramHandle,
    current_pipeline_layout: c.VkPipelineLayout,
    current_uniform_bindings: std.AutoHashMap(gfx.NameHandle, UniformBinding) = undefined,

    pub fn reset(self: *CommandBuffer) void {
        self.current_uniform_bindings.clearRetainingCapacity();
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

fn handlePushDescriptorSet(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
) !void {
    var command_buffer = get(command_buffer_handle);
    const program = vk.programs.get(program_handle);
    const pipeline_layout = program.pipeline_layout;
    const layout_count = program.layout_count;
    var write_descriptor_sets = &program.write_descriptor_sets;
    var buffer_infos: [vk.pipelines.MaxDescriptorSetBindings]c.VkDescriptorBufferInfo = undefined;
    var image_infos: [vk.pipelines.MaxDescriptorSetBindings]c.VkDescriptorImageInfo = undefined;

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
        .current_pipeline_layout = null,
        .current_program_handle = undefined,
        .current_uniform_bindings = .init(vk.gpa),
    };

    vk.log.debug("Created command buffer", .{});

    return .{ .handle = @ptrCast(command_buffer_ptr) };
}

pub fn destroy(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.deinit();
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

    const command_buffer = get(command_buffer_handle);

    const color_attachments = try vk.arena.alloc(
        c.VkRenderingAttachmentInfoKHR,
        options.color_attachments.len,
    );

    for (options.color_attachments, 0..) |color_attachment, i| {
        const image: *const vk.images.Image = @ptrCast(@alignCast(color_attachment.image.handle));
        const image_view: c.VkImageView = @ptrCast(@alignCast(color_attachment.image_view.handle));

        try vk.images.setImageLayout(
            command_buffer.handle,
            image.image,
            image.current_layout,
            c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        );

        const resolve_mode: c.VkResolveModeFlagBits = switch (color_attachment.resolve_mode) {
            .none => c.VK_RESOLVE_MODE_NONE,
            .sample_zero => c.VK_RESOLVE_MODE_SAMPLE_ZERO_BIT,
            .average => c.VK_RESOLVE_MODE_AVERAGE_BIT,
            .min => c.VK_RESOLVE_MODE_MIN_BIT,
            .max => c.VK_RESOLVE_MODE_MAX_BIT,
        };

        if (color_attachment.resolve_image) |resolve_image_handle| {
            const resolve_image: *const vk.images.Image = @ptrCast(@alignCast(resolve_image_handle.handle));
            try vk.images.setImageLayout(
                command_buffer.handle,
                resolve_image.image,
                resolve_image.current_layout,
                c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            );
        }

        var resolve_image_view: c.VkImageView = @ptrCast(c.VK_NULL_HANDLE);
        if (color_attachment.resolve_image_view) |resolve_image| {
            resolve_image_view = @ptrCast(@alignCast(resolve_image.handle));
        }

        color_attachments[i] = std.mem.zeroInit(
            c.VkRenderingAttachmentInfoKHR,
            .{
                .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO_KHR,
                .imageView = image_view,
                .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                .resolveMode = resolve_mode,
                .resolveImageView = resolve_image_view,
                .resolveImageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
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

        try vk.images.setImageLayout(
            command_buffer.handle,
            image.image,
            image.current_layout,
            c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
            c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
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
}

pub fn endRenderPass(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdEndRenderingKHR(command_buffer.handle);
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

pub fn bindPipeline(
    command_buffer_handle: gfx.CommandBufferHandle,
    pipeline_handle: gfx.PipelineHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    const pipeline = vk.pipelines.get(pipeline_handle);

    vk.device.cmdBindPipeline(
        command_buffer.handle,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline.handle,
    );

    const program = vk.programs.get(pipeline.program_handle);
    command_buffer.current_pipeline_layout = program.pipeline_layout;
    command_buffer.current_program_handle = pipeline.program_handle;
}

pub fn bindVertexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    vertex_buffer_handle: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    var offsets = [_]c.VkDeviceSize{offset};

    vk.device.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        &vk.buffers.get(vertex_buffer_handle).buffer,
        @ptrCast(&offsets),
    );
}

pub fn bindIndexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_buffer_handle: gfx.BufferHandle,
    offset: u32,
    index_type: types.IndexType,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdBindIndexBuffer(
        command_buffer.handle,
        vk.buffers.get(index_buffer_handle).buffer,
        offset,
        switch (index_type) {
            .u8 => c.VK_INDEX_TYPE_UINT8_EXT,
            .u16 => c.VK_INDEX_TYPE_UINT16,
            .u32 => c.VK_INDEX_TYPE_UINT32,
        },
    );
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
    vk.device.cmdPushConstants(
        command_buffer.handle,
        command_buffer.current_pipeline_layout,
        switch (shader_stage) {
            .vertex => c.VK_SHADER_STAGE_VERTEX_BIT,
            .fragment => c.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        offset,
        size,
        data,
    );
}

pub fn draw(
    command_buffer_handle: gfx.CommandBufferHandle,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    const current_program = command_buffer.current_program_handle;

    handlePushDescriptorSet(
        command_buffer_handle,
        current_program,
    ) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
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
) void {
    const command_buffer = get(command_buffer_handle);
    const current_program = command_buffer.current_program_handle;

    handlePushDescriptorSet(
        command_buffer_handle,
        current_program,
    ) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
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
