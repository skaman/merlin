const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const CommandBuffers = struct {
    const Self = @This();
    const MaxCommandBuffers = 16;

    device: *const vk.Device,
    command_pool: *const vk.CommandPool,
    handles: [MaxCommandBuffers]c.VkCommandBuffer,
    count: u32,

    pub fn init(
        device: *const vk.Device,
        command_pool: *const vk.CommandPool,
        count: u32,
    ) !Self {
        std.debug.assert(count <= MaxCommandBuffers);

        var handles: [MaxCommandBuffers]c.VkCommandBuffer = undefined;
        const allocate_info = std.mem.zeroInit(
            c.VkCommandBufferAllocateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = command_pool.handle,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = count,
            },
        );

        try device.allocateCommandBuffers(
            &allocate_info,
            &handles,
        );

        return .{
            .device = device,
            .command_pool = command_pool,
            .handles = handles,
            .count = count,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.freeCommandBuffers(
            self.command_pool.handle,
            self.count,
            &self.handles,
        );
    }

    pub fn begin(self: *Self, index: u32, one_time_submit: bool) !void {
        std.debug.assert(index < self.count);

        var begin_info = std.mem.zeroInit(
            c.VkCommandBufferBeginInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            },
        );

        if (one_time_submit) {
            begin_info.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        }

        try self.device.beginCommandBuffer(self.handles[index], &begin_info);
    }

    pub fn end(self: *Self, index: u32) !void {
        std.debug.assert(index < self.count);

        try self.device.endCommandBuffer(self.handles[index]);
    }

    pub fn reset(self: *Self, index: u32) !void {
        std.debug.assert(index < self.count);

        try self.device.resetCommandBuffer(self.handles[index], 0);
    }

    pub fn beginRenderPass(
        self: *Self,
        index: u32,
        render_pass: c.VkRenderPass,
        framebuffer: c.VkFramebuffer,
        extent: c.VkExtent2D,
    ) void {
        std.debug.assert(framebuffer != null);
        std.debug.assert(render_pass != null);
        std.debug.assert(index < self.count);

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
                .clearValueCount = 1,
                .pClearValues = &[_]c.VkClearValue{
                    .{
                        .color = .{
                            .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
                        },
                    },
                },
            },
        );

        try self.device.cmdBeginRenderPass(
            self.handles[index],
            &begin_info,
            c.VK_SUBPASS_CONTENTS_INLINE,
        );
    }

    pub fn endRenderPass(self: *Self, index: u32) void {
        std.debug.assert(index < self.count);

        self.device.cmdEndRenderPass(self.handles[index]);
    }

    pub fn setViewport(self: *Self, index: u32, viewport: *const c.VkViewport) void {
        std.debug.assert(index < self.count);

        self.device.cmdSetViewport(
            self.handles[index],
            0,
            1,
            viewport,
        );
    }

    pub fn setScissor(self: *Self, index: u32, scissor: *const c.VkRect2D) void {
        std.debug.assert(index < self.count);

        self.device.cmdSetScissor(
            self.handles[index],
            0,
            1,
            scissor,
        );
    }

    pub fn bindPipeline(self: *Self, index: u32, pipeline: c.VkPipeline) void {
        std.debug.assert(pipeline != null);
        std.debug.assert(index < self.count);

        self.device.cmdBindPipeline(
            self.handles[index],
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline,
        );
    }

    pub fn bindVertexBuffer(
        self: *Self,
        index: u32,
        buffer: c.VkBuffer,
        offsets: [*c]c.VkDeviceSize,
    ) void {
        std.debug.assert(buffer != null);
        std.debug.assert(offsets != null);
        std.debug.assert(index < self.count);

        const buffers = &buffer;
        self.device.cmdBindVertexBuffers(
            self.handles[index],
            0,
            1,
            buffers,
            offsets,
        );
    }

    pub fn bindIndexBuffer(
        self: *Self,
        index: u32,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        index_type: c.VkIndexType,
    ) void {
        std.debug.assert(buffer != null);
        std.debug.assert(index < self.count);

        self.device.cmdBindIndexBuffer(
            self.handles[index],
            buffer,
            offset,
            index_type,
        );
    }

    pub fn bindDescriptorSets(
        self: *Self,
        index: u32,
        pipeline_layout: c.VkPipelineLayout,
        first_set: u32,
        descriptor_set_count: u32,
        descriptor_sets: [*c]c.VkDescriptorSet,
        dynamic_offset_count: u32,
        dynamic_offsets: [*c]u32,
    ) void {
        std.debug.assert(pipeline_layout != null);
        std.debug.assert(descriptor_sets != null);
        std.debug.assert(index < self.count);

        self.device.cmdBindDescriptorSets(
            self.handles[index],
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline_layout,
            first_set,
            descriptor_set_count,
            descriptor_sets,
            dynamic_offset_count,
            dynamic_offsets,
        );
    }

    pub fn pushDescriptorSet(
        self: *const Self,
        index: u32,
        pipeline_layout: c.VkPipelineLayout,
        set: u32,
        descriptor_write_count: u32,
        descriptor_writes: [*c]const c.VkWriteDescriptorSet,
    ) void {
        std.debug.assert(pipeline_layout != null);
        std.debug.assert(descriptor_writes != null);
        std.debug.assert(index < self.count);

        self.device.cmdPushDescriptorSet(
            self.handles[index],
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline_layout,
            set,
            descriptor_write_count,
            descriptor_writes,
        );
    }

    pub fn draw(
        self: *Self,
        index: u32,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        std.debug.assert(index < self.count);

        self.device.cmdDraw(
            self.handles[index],
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
        );
    }

    pub fn drawIndexed(
        self: *Self,
        index: u32,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        std.debug.assert(index < self.count);

        self.device.cmdDrawIndexed(
            self.handles[index],
            index_count,
            instance_count,
            first_index,
            vertex_offset,
            first_instance,
        );
    }

    pub fn copyBuffer(
        self: *Self,
        index: u32,
        src_buffer: c.VkBuffer,
        dst_buffer: c.VkBuffer,
        region_count: u32,
        regions: [*c]const c.VkBufferCopy,
    ) void {
        std.debug.assert(src_buffer != null);
        std.debug.assert(dst_buffer != null);
        std.debug.assert(regions != null);
        std.debug.assert(index < self.count);

        self.device.cmdCopyBuffer(
            self.handles[index],
            src_buffer,
            dst_buffer,
            region_count,
            regions,
        );
    }
};
