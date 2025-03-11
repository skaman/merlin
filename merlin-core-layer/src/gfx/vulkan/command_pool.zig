const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const CommandPool = struct {
    const Self = @This();

    handle: c.VkCommandPool,

    pub fn init(queue_family_index: u32) !Self {
        const create_info = std.mem.zeroInit(
            c.VkCommandPoolCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .queueFamilyIndex = queue_family_index,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            },
        );

        var command_pool: c.VkCommandPool = undefined;
        try vk.device.createCommandPool(
            &create_info,
            &command_pool,
        );
        errdefer vk.device.destroyCommandPool(command_pool);

        return .{ .handle = command_pool };
    }

    pub fn deinit(self: *Self) void {
        vk.device.destroyCommandPool(self.handle);
    }
};
