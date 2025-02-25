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
        queue: c.VkQueue,
        queue_family_index: u32,
        data: [*]const u8,
        size: u32,
        index_type: gfx.IndexType,
    ) !Self {
        var staging_buffer = try vk.Buffer.init(
            device,
            size,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        defer staging_buffer.deinit();

        var mapped_data: [*c]u8 = undefined;
        try device.mapMemory(
            staging_buffer.memory,
            0,
            size,
            0,
            @ptrCast(&mapped_data),
        );
        defer device.unmapMemory(staging_buffer.memory);

        @memcpy(mapped_data[0..size], data[0..size]);

        var buffer = try vk.Buffer.init(
            device,
            size,
            c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        );
        errdefer buffer.deinit();

        try buffer.copyFromBuffer(
            queue,
            queue_family_index,
            staging_buffer.handle,
            size,
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
