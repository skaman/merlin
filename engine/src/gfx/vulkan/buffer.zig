const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Buffer = struct {
    const Self = @This();

    device: *const vk.Device,
    handle: c.VkBuffer,
    device_memory: c.VkDeviceMemory,

    pub fn init(
        device: *const vk.Device,
        size: c.VkDeviceSize,
        usage: c.VkBufferUsageFlags,
        data: ?[*]const u8,
    ) !Self {
        const buffer_info = std.mem.zeroInit(
            c.VkBufferCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                .size = size,
                .usage = usage,
                .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            },
        );

        var handle: c.VkBuffer = undefined;
        try device.createBuffer(
            &buffer_info,
            &handle,
        );
        errdefer device.destroyBuffer(handle);

        var requirements: c.VkMemoryRequirements = undefined;
        device.getBufferMemoryRequirements(handle, &requirements);

        const memory = try allocateMemory(
            device,
            &requirements,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        errdefer device.freeMemory(memory);

        try device.bindBufferMemory(handle, memory, 0);

        if (data) |data_value| {
            var mapped_data: [*c]u8 = undefined;
            try device.mapMemory(memory, 0, size, 0, @ptrCast(&mapped_data));
            defer device.unmapMemory(memory);

            @memcpy(mapped_data[0..size], data_value[0..size]);
        }

        return .{
            .device = device,
            .handle = handle,
            .device_memory = memory,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyBuffer(self.handle);
        self.device.freeMemory(self.device_memory);
    }

    fn findMemoryTypeIndex(
        device: *const vk.Device,
        memory_type_bits: u32,
        property_flags: c.VkMemoryPropertyFlags,
    ) !u32 {
        var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        device.getPhysicalDeviceMemoryProperties(
            device.physical_device,
            &memory_properties,
        );

        for (0..memory_properties.memoryTypeCount) |index| {
            if (memory_type_bits & (@as(u32, 1) << @as(u5, @intCast(index))) != 0 and
                memory_properties.memoryTypes[index].propertyFlags & property_flags == property_flags)
            {
                return @intCast(index);
            }
        }

        vk.log.err("Failed to find suitable memory type", .{});

        return error.MemoryTypeNotFound;
    }

    fn allocateMemory(
        device: *const vk.Device,
        requirements: *c.VkMemoryRequirements,
        property_flags: c.VkMemoryPropertyFlags,
    ) !c.VkDeviceMemory {
        const memory_type_index = try findMemoryTypeIndex(
            device,
            requirements.memoryTypeBits,
            property_flags,
        );

        const allocate_info = std.mem.zeroInit(
            c.VkMemoryAllocateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                .allocationSize = requirements.size,
                .memoryTypeIndex = memory_type_index,
            },
        );

        var memory: c.VkDeviceMemory = undefined;
        try device.allocateMemory(
            &allocate_info,
            &memory,
        );
        return memory;
    }
};
