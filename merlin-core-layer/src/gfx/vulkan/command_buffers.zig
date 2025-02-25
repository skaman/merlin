const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const CommandBuffers = struct {
    const Self = @This();
    const MaxCommandBuffers = 16;

    command_pool: c.VkCommandPool,
    handles: [MaxCommandBuffers]c.VkCommandBuffer,
    device: *const vk.Device,

    pub fn init(
        device: *const vk.Device,
        count: u32,
        queue_family_index: u32,
    ) !Self {
        std.debug.assert(count <= MaxCommandBuffers);

        const create_info = std.mem.zeroInit(
            c.VkCommandPoolCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .queueFamilyIndex = queue_family_index,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            },
        );

        var command_pool: c.VkCommandPool = undefined;
        try device.createCommandPool(
            &create_info,
            &command_pool,
        );
        errdefer device.destroyCommandPool(command_pool);

        var handles: [MaxCommandBuffers]c.VkCommandBuffer = undefined;
        const allocate_info = std.mem.zeroInit(
            c.VkCommandBufferAllocateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = command_pool,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = count,
            },
        );

        try device.allocateCommandBuffers(
            &allocate_info,
            &handles,
        );

        return .{
            .command_pool = command_pool,
            .device = device,
            .handles = handles,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyCommandPool(self.command_pool);
    }

    pub fn begin(self: *Self, index: u32, one_time_submit: bool) !void {
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
        try self.device.endCommandBuffer(self.handles[index]);
    }

    pub fn reset(self: *Self, index: u32) !void {
        try self.device.resetCommandBuffer(self.handles[index], 0);
    }

    pub fn beginRenderPass(
        self: *Self,
        index: u32,
        render_pass: c.VkRenderPass,
        framebuffer: c.VkFramebuffer,
        extent: c.VkExtent2D,
    ) void {
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
        self.device.cmdEndRenderPass(self.handles[index]);
    }

    pub fn setViewport(self: *Self, index: u32, viewport: c.VkViewport) void {
        self.device.cmdSetViewport(
            self.handles[index],
            0,
            1,
            &viewport,
        );
    }

    pub fn setScissor(self: *Self, index: u32, scissor: c.VkRect2D) void {
        self.device.cmdSetScissor(
            self.handles[index],
            0,
            1,
            &scissor,
        );
    }

    pub fn bindPipeline(self: *Self, index: u32, pipeline: c.VkPipeline) void {
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
        self.device.cmdBindIndexBuffer(
            self.handles[index],
            buffer,
            offset,
            index_type,
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
        self.device.cmdCopyBuffer(
            self.handles[index],
            src_buffer,
            dst_buffer,
            region_count,
            regions,
        );
    }
};
