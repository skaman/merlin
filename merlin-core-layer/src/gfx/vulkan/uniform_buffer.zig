const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const UniformBuffer = struct {
    const Self = @This();

    buffer: vk.Buffer,
    mapped_data: [*c]u8,
    mapped_data_size: u32,

    pub fn init(size: u32) !Self {
        var buffer = try vk.Buffer.init(
            size,
            c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        errdefer buffer.deinit();

        var mapped_data: [*c]u8 = undefined;
        try vk.device.mapMemory(
            buffer.memory,
            0,
            size,
            0,
            @ptrCast(&mapped_data),
        );
        errdefer vk.device.unmapMemory(buffer.memory);

        return .{
            .buffer = buffer,
            .mapped_data = mapped_data,
            .mapped_data_size = size,
        };
    }

    pub fn deinit(self: *Self) void {
        vk.device.unmapMemory(self.buffer.memory);
        self.buffer.deinit();
    }

    pub fn update(self: *Self, data: []const u8) void {
        std.debug.assert(data.len <= self.mapped_data_size);

        @memcpy(self.mapped_data[0..data.len], data);
    }
};
