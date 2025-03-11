const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const VertexBuffer = struct {
    const Self = @This();

    buffer: vk.buffer.Buffer,
    layout: gfx.VertexLayout,

    pub fn init(
        command_pool: c.VkCommandPool,
        queue: c.VkQueue,
        layout: gfx.VertexLayout,
        data: []const u8,
    ) !Self {
        var staging_buffer = try vk.buffer.create(
            @intCast(data.len),
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        defer vk.buffer.destroy(&staging_buffer);

        var mapped_data: [*c]u8 = undefined;
        try vk.device.mapMemory(
            staging_buffer.memory,
            0,
            @intCast(data.len),
            0,
            @ptrCast(&mapped_data),
        );
        defer vk.device.unmapMemory(staging_buffer.memory);

        @memcpy(mapped_data[0..data.len], data);

        var buffer = try vk.buffer.create(
            @intCast(data.len),
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer vk.buffer.destroy(&buffer);

        try vk.buffer.copyBuffer(
            command_pool,
            queue,
            staging_buffer.handle,
            buffer.handle,
            @intCast(data.len),
        );

        return .{
            .buffer = buffer,
            .layout = layout,
        };
    }

    pub fn deinit(self: *Self) void {
        vk.buffer.destroy(&self.buffer);
    }
};
