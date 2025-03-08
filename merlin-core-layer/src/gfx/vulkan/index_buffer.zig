const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const IndexBuffer = struct {
    const Self = @This();

    buffer: vk.Buffer,
    index_type: gfx.IndexType,

    pub fn init(
        device: *const vk.Device,
        command_pool: *const vk.CommandPool,
        queue: c.VkQueue,
        data: []const u8,
        index_type: gfx.IndexType,
    ) !Self {
        std.debug.assert(queue != null);
        std.debug.assert(data.len > 0);

        var staging_buffer = try vk.Buffer.init(
            device,
            @intCast(data.len),
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        defer staging_buffer.deinit();

        var mapped_data: [*c]u8 = undefined;
        try device.mapMemory(
            staging_buffer.memory,
            0,
            @intCast(data.len),
            0,
            @ptrCast(&mapped_data),
        );
        defer device.unmapMemory(staging_buffer.memory);

        @memcpy(mapped_data[0..data.len], data);

        var buffer = try vk.Buffer.init(
            device,
            @intCast(data.len),
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer buffer.deinit();

        try buffer.copyFromBuffer(
            command_pool,
            queue,
            staging_buffer.handle,
            @intCast(data.len),
        );

        return .{
            .buffer = buffer,
            .index_type = index_type,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }
};
