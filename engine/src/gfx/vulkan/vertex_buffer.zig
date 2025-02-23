const std = @import("std");

const shared = @import("shared");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const VertexBuffer = struct {
    const Self = @This();

    buffer: vk.Buffer,
    layout: shared.VertexLayout,

    pub fn init(
        device: *const vk.Device,
        layout: shared.VertexLayout,
        data: ?[*]const u8,
        size: u32,
    ) !Self {
        const buffer = try vk.Buffer.init(
            device,
            size,
            c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            data,
        );
        return .{
            .buffer = buffer,
            .layout = layout,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }
};
