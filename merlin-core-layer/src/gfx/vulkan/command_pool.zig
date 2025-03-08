const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const CommandPool = struct {
    const Self = @This();

    handle: c.VkCommandPool,
    //queue_family_index: u32,
    device: *const vk.Device,

    pub fn init(
        device: *const vk.Device,
        queue_family_index: u32,
    ) !Self {
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

        return .{
            .handle = command_pool,
            //.queue_family_index = queue_family_index,
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyCommandPool(self.handle);
    }
};
