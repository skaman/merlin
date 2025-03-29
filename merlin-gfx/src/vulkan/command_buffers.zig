const std = @import("std");

const utils = @import("merlin_utils");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const CommandBuffer = struct {
    command_pool: c.VkCommandPool,
    handle: c.VkCommandBuffer,
    current_program: ?gfx.ProgramHandle = null,
    current_vertex_buffer: ?gfx.VertexBufferHandle = null,
    current_index_buffer: ?gfx.IndexBufferHandle = null,
    last_pipeline_layout: ?gfx.PipelineLayoutHandle = null,
    last_pipeline_program: ?gfx.ProgramHandle = null,
    last_vertex_buffer: ?gfx.VertexBufferHandle = null,
    last_index_buffer: ?gfx.IndexBufferHandle = null,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var command_buffers: [gfx.MaxCommandBufferHandles]CommandBuffer = undefined;
var command_buffer_handles: utils.HandlePool(gfx.CommandBufferHandle, gfx.MaxCommandBufferHandles) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn handleBindPipeline(handle: gfx.CommandBufferHandle, program_handle: gfx.ProgramHandle) !void {
    const layout_handle = vk.vertex_buffers.layout(command_buffers[handle].current_vertex_buffer.?);
    if (command_buffers[handle].last_pipeline_program == program_handle and
        command_buffers[handle].last_pipeline_layout == layout_handle)
    {
        return;
    }

    const command_buffer = command_buffers[handle].handle;
    const pipeline = try vk.pipeline.pipeline(
        program_handle,
        layout_handle,
    );

    vk.device.cmdBindPipeline(
        command_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline,
    );

    command_buffers[handle].last_pipeline_program = program_handle;
    command_buffers[handle].last_pipeline_layout = layout_handle;
}

fn handleBindVertexBuffer(handle: gfx.CommandBufferHandle) !void {
    const vertex_buffer = command_buffers[handle].current_vertex_buffer.?;
    if (command_buffers[handle].last_vertex_buffer == vertex_buffer) {
        return;
    }

    const command_buffer = command_buffers[handle].handle;
    var offsets = [_]c.VkDeviceSize{0};

    vk.device.cmdBindVertexBuffers(
        command_buffer,
        0,
        1,
        &vk.vertex_buffers.buffer(vertex_buffer),
        @ptrCast(&offsets),
    );

    command_buffers[handle].last_vertex_buffer = vertex_buffer;
}

fn handleBindIndexBuffer(handle: gfx.CommandBufferHandle) !void {
    const index_buffer = command_buffers[handle].current_index_buffer.?;
    if (command_buffers[handle].last_index_buffer == index_buffer) {
        return;
    }

    const command_buffer = command_buffers[handle].handle;
    const index_type: c_uint = switch (vk.index_buffers.getIndexType(index_buffer)) {
        .u8 => c.VK_INDEX_TYPE_UINT8_EXT,
        .u16 => c.VK_INDEX_TYPE_UINT16,
        .u32 => c.VK_INDEX_TYPE_UINT32,
    };

    vk.device.cmdBindIndexBuffer(
        command_buffer,
        vk.index_buffers.getBuffer(index_buffer),
        0,
        index_type,
    );

    command_buffers[handle].last_index_buffer = index_buffer;
}

fn handlePushDescriptorSet(handle: gfx.CommandBufferHandle, program_handle: gfx.ProgramHandle) !void {
    const command_buffer = command_buffers[handle].handle;
    const pipeline_layout = vk.programs.pipelineLayout(program_handle);
    const layout_count = vk.programs.layoutCount(program_handle);
    var write_descriptor_sets = vk.programs.writeDescriptorSets(program_handle);

    for (0..layout_count) |binding_index| {
        const uniform_handle = vk.programs.uniformHandle(program_handle, @intCast(binding_index));
        const descriptor_type = vk.programs.descriptorType(program_handle, @intCast(binding_index));

        switch (descriptor_type) {
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                write_descriptor_sets[binding_index].pBufferInfo = &.{
                    .buffer = vk.descriptor_registry.getBuffer(uniform_handle),
                    .offset = 0,
                    .range = vk.descriptor_registry.getBufferSize(uniform_handle),
                };
            },
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => {
                const texture_handle = vk.descriptor_registry.getCombinedSamplerTexture(uniform_handle);
                if (texture_handle) |texture_handle_value| {
                    write_descriptor_sets[binding_index].pImageInfo = &.{
                        .imageLayout = vk.textures.getImageLayout(texture_handle_value),
                        .imageView = vk.textures.getImageView(texture_handle_value),
                        .sampler = vk.textures.getSampler(texture_handle_value),
                    };
                } else {
                    vk.log.err("Texture handle is null for descriptor {d}", .{binding_index});
                    return error.TextureHandleIsNull;
                }
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
        command_buffer,
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

pub fn init() void {
    command_buffer_handles = .init();
}

pub fn deinit() void {
    command_buffer_handles.deinit();
}

pub fn create(command_pool: c.VkCommandPool) !gfx.CommandBufferHandle {
    var command_buffer: c.VkCommandBuffer = undefined;
    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );
    errdefer vk.device.freeCommandBuffers(
        command_pool,
        1,
        &command_buffer,
    );

    const handle = try command_buffer_handles.alloc();
    errdefer command_buffer_handles.free(command_buffer);

    command_buffers[handle] = CommandBuffer{
        .command_pool = command_pool,
        .handle = command_buffer,
    };

    vk.log.debug("Created command buffer:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroy(handle: gfx.CommandBufferHandle) void {
    const command_buffer = command_buffers[handle];

    vk.device.freeCommandBuffers(
        command_buffer.command_pool,
        1,
        &command_buffer.handle,
    );

    command_buffer_handles.free(handle);

    vk.log.debug("Destroyed command buffer with handle {d}", .{handle});
}

pub fn beginSingleTimeCommands(command_pool: c.VkCommandPool) !c.VkCommandBuffer {
    var command_buffer: c.VkCommandBuffer = undefined;
    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );

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

pub fn commandBuffer(handle: gfx.CommandBufferHandle) c.VkCommandBuffer {
    return command_buffers[handle].handle;
}

pub fn reset(handle: gfx.CommandBufferHandle) !void {
    var command_buffer = &command_buffers[handle];

    try vk.device.resetCommandBuffer(command_buffer.handle, 0);

    command_buffer.current_program = null;
    command_buffer.current_vertex_buffer = null;
    command_buffer.current_index_buffer = null;

    command_buffer.last_pipeline_program = null;
    command_buffer.last_pipeline_layout = null;
    command_buffer.last_vertex_buffer = null;
    command_buffer.last_index_buffer = null;
}

pub fn begin(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = command_buffers[handle];

    const begin_info = std.mem.zeroInit(
        c.VkCommandBufferBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        },
    );

    try vk.device.beginCommandBuffer(command_buffer.handle, &begin_info);
}

pub fn end(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = command_buffers[handle];

    try vk.device.endCommandBuffer(command_buffer.handle);
}

pub fn beginRenderPass(
    handle: gfx.CommandBufferHandle,
    render_pass: c.VkRenderPass,
    framebuffer: c.VkFramebuffer,
    extent: c.VkExtent2D,
) !void {
    std.debug.assert(framebuffer != null);
    std.debug.assert(render_pass != null);

    const clear_values = [_]c.VkClearValue{
        .{
            .color = .{
                .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
        .{
            .depthStencil = .{
                .depth = 1.0,
                .stencil = 0,
            },
        },
    };

    const begin_info = std.mem.zeroInit(
        c.VkRenderPassBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = render_pass,
            .framebuffer = framebuffer,
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = extent,
            },
            .clearValueCount = clear_values.len,
            .pClearValues = &clear_values,
        },
    );

    const command_buffer = command_buffers[handle].handle;

    try vk.device.cmdBeginRenderPass(
        command_buffer,
        &begin_info,
        c.VK_SUBPASS_CONTENTS_INLINE,
    );
}

pub fn endRenderPass(handle: gfx.CommandBufferHandle) void {
    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdEndRenderPass(command_buffer);
}

pub fn setViewport(handle: gfx.CommandBufferHandle, viewport: *const c.VkViewport) void {
    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdSetViewport(
        command_buffer,
        0,
        1,
        viewport,
    );
}

pub fn setScissor(handle: gfx.CommandBufferHandle, scissor: *const c.VkRect2D) void {
    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdSetScissor(
        command_buffer,
        0,
        1,
        scissor,
    );
}

pub fn bindProgram(
    handle: gfx.CommandBufferHandle,
    program: gfx.ProgramHandle,
) void {
    command_buffers[handle].current_program = program;
}

pub fn bindVertexBuffer(
    handle: gfx.CommandBufferHandle,
    vertex_buffer: gfx.VertexBufferHandle,
) void {
    command_buffers[handle].current_vertex_buffer = vertex_buffer;
}

pub fn bindIndexBuffer(
    handle: gfx.CommandBufferHandle,
    index_buffer: gfx.IndexBufferHandle,
) void {
    command_buffers[handle].current_index_buffer = index_buffer;
}

pub fn draw(
    handle: gfx.CommandBufferHandle,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    const command_buffer = command_buffers[handle].handle;
    const current_program = command_buffers[handle].current_program;

    handleBindPipeline(handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan program: {d}", .{current_program.?});
        return;
    };

    handleBindVertexBuffer(handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    vk.device.cmdDraw(
        command_buffer,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    handle: gfx.CommandBufferHandle,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    const command_buffer = command_buffers[handle].handle;
    const current_program = command_buffers[handle].current_program;

    handleBindPipeline(handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan program: {d}", .{current_program.?});
        return;
    };

    handleBindVertexBuffer(handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    handleBindIndexBuffer(handle) catch {
        vk.log.err("Failed to bind Vulkan index buffer", .{});
        return;
    };

    vk.device.cmdDrawIndexed(
        command_buffer,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
