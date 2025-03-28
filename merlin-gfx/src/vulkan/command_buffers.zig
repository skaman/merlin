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
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var command_buffers: [gfx.MaxCommandBufferHandles]CommandBuffer = undefined;
var command_buffer_handles: utils.HandlePool(gfx.CommandBufferHandle, gfx.MaxCommandBufferHandles) = undefined;

// *********************************************************************************************
// CommandBuffers
// *********************************************************************************************

//pub const CommandBuffers = struct {
//    command_pool: c.VkCommandPool,
//    handles: [MaxCommandBuffers]c.VkCommandBuffer,
//    count: u32,
//
//    pub inline fn begin(self: *CommandBuffers, index: u32, one_time_submit: bool) !void {
//        std.debug.assert(index < self.count);
//
//        var begin_info = std.mem.zeroInit(
//            c.VkCommandBufferBeginInfo,
//            .{
//                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
//            },
//        );
//
//        if (one_time_submit) {
//            begin_info.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
//        }
//
//        try vk.device.beginCommandBuffer(self.handles[index], &begin_info);
//    }
//
//    pub inline fn end(self: *CommandBuffers, index: u32) !void {
//        std.debug.assert(index < self.count);
//
//        try vk.device.endCommandBuffer(self.handles[index]);
//    }
//
//    pub inline fn reset(self: *CommandBuffers, index: u32) !void {
//        std.debug.assert(index < self.count);
//
//        try vk.device.resetCommandBuffer(self.handles[index], 0);
//    }
//
//    pub inline fn beginRenderPass(
//        self: *CommandBuffers,
//        index: u32,
//        render_pass: c.VkRenderPass,
//        framebuffer: c.VkFramebuffer,
//        extent: c.VkExtent2D,
//    ) void {
//        std.debug.assert(framebuffer != null);
//        std.debug.assert(render_pass != null);
//        std.debug.assert(index < self.count);
//
//        const clear_values = [_]c.VkClearValue{
//            .{
//                .color = .{
//                    .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
//                },
//            },
//            .{
//                .depthStencil = .{
//                    .depth = 1.0,
//                    .stencil = 0,
//                },
//            },
//        };
//
//        const begin_info = std.mem.zeroInit(
//            c.VkRenderPassBeginInfo,
//            .{
//                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
//                .renderPass = render_pass,
//                .framebuffer = framebuffer,
//                .renderArea = .{
//                    .offset = .{ .x = 0, .y = 0 },
//                    .extent = extent,
//                },
//                .clearValueCount = clear_values.len,
//                .pClearValues = &clear_values,
//            },
//        );
//
//        try vk.device.cmdBeginRenderPass(
//            self.handles[index],
//            &begin_info,
//            c.VK_SUBPASS_CONTENTS_INLINE,
//        );
//    }
//
//    pub inline fn endRenderPass(self: *CommandBuffers, index: u32) void {
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdEndRenderPass(self.handles[index]);
//    }
//
//    pub inline fn setViewport(self: *CommandBuffers, index: u32, viewport: *const c.VkViewport) void {
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdSetViewport(
//            self.handles[index],
//            0,
//            1,
//            viewport,
//        );
//    }
//
//    pub inline fn setScissor(self: *CommandBuffers, index: u32, scissor: *const c.VkRect2D) void {
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdSetScissor(
//            self.handles[index],
//            0,
//            1,
//            scissor,
//        );
//    }
//
//    pub inline fn bindPipeline(self: *CommandBuffers, index: u32, pipeline: c.VkPipeline) void {
//        std.debug.assert(pipeline != null);
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdBindPipeline(
//            self.handles[index],
//            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
//            pipeline,
//        );
//    }
//
//    pub inline fn bindVertexBuffer(
//        self: *CommandBuffers,
//        index: u32,
//        buffer: c.VkBuffer,
//        offsets: [*c]c.VkDeviceSize,
//    ) void {
//        std.debug.assert(buffer != null);
//        std.debug.assert(offsets != null);
//        std.debug.assert(index < self.count);
//
//        const buffers = &buffer;
//        vk.device.cmdBindVertexBuffers(
//            self.handles[index],
//            0,
//            1,
//            buffers,
//            offsets,
//        );
//    }
//
//    pub inline fn bindIndexBuffer(
//        self: *CommandBuffers,
//        index: u32,
//        buffer: c.VkBuffer,
//        offset: c.VkDeviceSize,
//        index_type: c.VkIndexType,
//    ) void {
//        std.debug.assert(buffer != null);
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdBindIndexBuffer(
//            self.handles[index],
//            buffer,
//            offset,
//            index_type,
//        );
//    }
//
//    pub inline fn bindDescriptorSets(
//        self: *CommandBuffers,
//        index: u32,
//        pipeline_layout: c.VkPipelineLayout,
//        first_set: u32,
//        descriptor_set_count: u32,
//        descriptor_sets: [*c]c.VkDescriptorSet,
//        dynamic_offset_count: u32,
//        dynamic_offsets: [*c]u32,
//    ) void {
//        std.debug.assert(pipeline_layout != null);
//        std.debug.assert(descriptor_sets != null);
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdBindDescriptorSets(
//            self.handles[index],
//            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
//            pipeline_layout,
//            first_set,
//            descriptor_set_count,
//            descriptor_sets,
//            dynamic_offset_count,
//            dynamic_offsets,
//        );
//    }
//
//    pub inline fn pushDescriptorSet(
//        self: *const CommandBuffers,
//        index: u32,
//        pipeline_layout: c.VkPipelineLayout,
//        set: u32,
//        descriptor_write_count: u32,
//        descriptor_writes: [*c]const c.VkWriteDescriptorSet,
//    ) void {
//        std.debug.assert(pipeline_layout != null);
//        std.debug.assert(descriptor_writes != null);
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdPushDescriptorSet(
//            self.handles[index],
//            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
//            pipeline_layout,
//            set,
//            descriptor_write_count,
//            descriptor_writes,
//        );
//    }
//
//    pub inline fn draw(
//        self: *CommandBuffers,
//        index: u32,
//        vertex_count: u32,
//        instance_count: u32,
//        first_vertex: u32,
//        first_instance: u32,
//    ) void {
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdDraw(
//            self.handles[index],
//            vertex_count,
//            instance_count,
//            first_vertex,
//            first_instance,
//        );
//    }
//
//    pub inline fn drawIndexed(
//        self: *CommandBuffers,
//        index: u32,
//        index_count: u32,
//        instance_count: u32,
//        first_index: u32,
//        vertex_offset: i32,
//        first_instance: u32,
//    ) void {
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdDrawIndexed(
//            self.handles[index],
//            index_count,
//            instance_count,
//            first_index,
//            vertex_offset,
//            first_instance,
//        );
//    }
//
//    pub inline fn copyBuffer(
//        self: *CommandBuffers,
//        index: u32,
//        src_buffer: c.VkBuffer,
//        dst_buffer: c.VkBuffer,
//        region_count: u32,
//        regions: [*c]const c.VkBufferCopy,
//    ) void {
//        std.debug.assert(src_buffer != null);
//        std.debug.assert(dst_buffer != null);
//        std.debug.assert(regions != null);
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdCopyBuffer(
//            self.handles[index],
//            src_buffer,
//            dst_buffer,
//            region_count,
//            regions,
//        );
//    }
//
//    pub inline fn pipelineBarrier(
//        self: *CommandBuffers,
//        index: u32,
//        src_stage_mask: c.VkPipelineStageFlags,
//        dst_stage_mask: c.VkPipelineStageFlags,
//        dependency_flags: c.VkDependencyFlags,
//        memory_barrier_count: u32,
//        memory_barriers: [*c]const c.VkMemoryBarrier,
//        buffer_memory_barrier_count: u32,
//        buffer_memory_barriers: [*c]const c.VkBufferMemoryBarrier,
//        image_memory_barrier_count: u32,
//        image_memory_barriers: [*c]const c.VkImageMemoryBarrier,
//    ) void {
//        std.debug.assert(index < self.count);
//
//        vk.device.cmdPipelineBarrier(
//            self.handles[index],
//            src_stage_mask,
//            dst_stage_mask,
//            dependency_flags,
//            memory_barrier_count,
//            memory_barriers,
//            buffer_memory_barrier_count,
//            buffer_memory_barriers,
//            image_memory_barrier_count,
//            image_memory_barriers,
//        );
//    }
//};

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
    const command_buffer = command_buffers[handle];

    try vk.device.resetCommandBuffer(command_buffer.handle, 0);
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

pub fn bindPipeline(handle: gfx.CommandBufferHandle, pipeline: c.VkPipeline) void {
    std.debug.assert(pipeline != null);

    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdBindPipeline(
        command_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline,
    );
}

pub fn bindVertexBuffer(
    handle: gfx.CommandBufferHandle,
    buffer: c.VkBuffer,
    offsets: [*c]c.VkDeviceSize,
) void {
    std.debug.assert(buffer != null);
    std.debug.assert(offsets != null);

    const buffers = &buffer;
    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdBindVertexBuffers(
        command_buffer,
        0,
        1,
        buffers,
        offsets,
    );
}

pub fn bindIndexBuffer(
    handle: gfx.CommandBufferHandle,
    buffer: c.VkBuffer,
    offset: c.VkDeviceSize,
    index_type: c.VkIndexType,
) void {
    std.debug.assert(buffer != null);

    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdBindIndexBuffer(
        command_buffer,
        buffer,
        offset,
        index_type,
    );
}

pub fn pushDescriptorSet(
    handle: gfx.CommandBufferHandle,
    pipeline_layout: c.VkPipelineLayout,
    set: u32,
    descriptor_write_count: u32,
    descriptor_writes: [*c]const c.VkWriteDescriptorSet,
) void {
    std.debug.assert(pipeline_layout != null);
    std.debug.assert(descriptor_writes != null);

    const command_buffer = command_buffers[handle].handle;

    vk.device.cmdPushDescriptorSet(
        command_buffer,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline_layout,
        set,
        descriptor_write_count,
        descriptor_writes,
    );
}

pub fn draw(
    handle: gfx.CommandBufferHandle,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    const command_buffer = command_buffers[handle].handle;

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

    vk.device.cmdDrawIndexed(
        command_buffer,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}
