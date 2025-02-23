const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const CommandQueue = struct {
    const Self = @This();
    const Dispatch = struct {
        BeginCommandBuffer: std.meta.Child(c.PFN_vkBeginCommandBuffer) = undefined,
        EndCommandBuffer: std.meta.Child(c.PFN_vkEndCommandBuffer) = undefined,
        ResetCommandBuffer: std.meta.Child(c.PFN_vkResetCommandBuffer) = undefined,
        CmdBeginRenderPass: std.meta.Child(c.PFN_vkCmdBeginRenderPass) = undefined,
        CmdEndRenderPass: std.meta.Child(c.PFN_vkCmdEndRenderPass) = undefined,
        CmdSetViewport: std.meta.Child(c.PFN_vkCmdSetViewport) = undefined,
        CmdSetScissor: std.meta.Child(c.PFN_vkCmdSetScissor) = undefined,
        CmdBindPipeline: std.meta.Child(c.PFN_vkCmdBindPipeline) = undefined,
        CmdBindVertexBuffers: std.meta.Child(c.PFN_vkCmdBindVertexBuffers) = undefined,
        CmdDraw: std.meta.Child(c.PFN_vkCmdDraw) = undefined,
    };

    command_pool: c.VkCommandPool,
    command_buffers: [vk.MaxFramesInFlight]c.VkCommandBuffer,
    device: *const vk.Device,
    dispatch: Dispatch,

    pub fn init(
        library: *vk.Library,
        device: *const vk.Device,
    ) !Self {
        const create_info = std.mem.zeroInit(
            c.VkCommandPoolCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .queueFamilyIndex = device.queue_family_indices.graphics_family.?,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            },
        );

        var command_pool: c.VkCommandPool = undefined;
        try device.createCommandPool(
            &create_info,
            &command_pool,
        );
        errdefer device.destroyCommandPool(command_pool);

        var command_buffers: [vk.MaxFramesInFlight]c.VkCommandBuffer = undefined;
        const allocate_info = std.mem.zeroInit(
            c.VkCommandBufferAllocateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = command_pool,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = command_buffers.len,
            },
        );

        try device.allocateCommandBuffers(
            &allocate_info,
            &command_buffers,
        );

        return .{
            .command_pool = command_pool,
            .device = device,
            .command_buffers = command_buffers,
            .dispatch = try library.load(Dispatch, device.instance.handle),
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyCommandPool(self.command_pool);
    }

    pub fn begin(self: *Self, frame_index: u32) !void {
        const begin_info = std.mem.zeroInit(
            c.VkCommandBufferBeginInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                //.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            },
        );

        try vk.checkVulkanError(
            "Failed to begin command buffer",
            self.dispatch.BeginCommandBuffer(self.command_buffers[frame_index], &begin_info),
        );
    }

    pub fn end(self: *Self, frame_index: u32) !void {
        try vk.checkVulkanError(
            "Failed to end command buffer",
            self.dispatch.EndCommandBuffer(self.command_buffers[frame_index]),
        );
    }

    pub fn reset(self: *Self, frame_index: u32) !void {
        try vk.checkVulkanError(
            "Failed to reset command buffer",
            self.dispatch.ResetCommandBuffer(self.command_buffers[frame_index], 0),
        );
    }

    pub fn beginRenderPass(
        self: *Self,
        render_pass: c.VkRenderPass,
        framebuffer: c.VkFramebuffer,
        extent: c.VkExtent2D,
        frame_index: u32,
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

        self.dispatch.CmdBeginRenderPass(
            self.command_buffers[frame_index],
            &begin_info,
            c.VK_SUBPASS_CONTENTS_INLINE,
        );
    }

    pub fn endRenderPass(self: *Self, frame_index: u32) void {
        self.dispatch.CmdEndRenderPass(self.command_buffers[frame_index]);
    }

    pub fn setViewport(self: *Self, viewport: c.VkViewport, frame_index: u32) void {
        self.dispatch.CmdSetViewport(self.command_buffers[frame_index], 0, 1, &viewport);
    }

    pub fn setScissor(self: *Self, scissor: c.VkRect2D, frame_index: u32) void {
        self.dispatch.CmdSetScissor(self.command_buffers[frame_index], 0, 1, &scissor);
    }

    pub fn bindPipeline(self: *Self, pipeline: c.VkPipeline, frame_index: u32) void {
        self.dispatch.CmdBindPipeline(
            self.command_buffers[frame_index],
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline,
        );
    }

    pub fn bindVertexBuffer(
        self: *Self,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        frame_index: u32,
    ) void {
        const buffers = &buffer;
        self.dispatch.CmdBindVertexBuffers(
            self.command_buffers[frame_index],
            0,
            1,
            buffers,
            &offset,
        );
    }

    pub fn draw(
        self: *Self,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
        frame_index: u32,
    ) void {
        self.dispatch.CmdDraw(
            self.command_buffers[frame_index],
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
        );
    }
};
