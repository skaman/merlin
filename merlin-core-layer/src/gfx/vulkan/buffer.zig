const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Buffer = struct {
    const Self = @This();

    device: *const vk.Device,
    handle: c.VkBuffer,
    memory: c.VkDeviceMemory,

    pub fn init(
        device: *const vk.Device,
        size: c.VkDeviceSize,
        usage: c.VkBufferUsageFlags,
        property_flags: c.VkMemoryPropertyFlags,
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
            property_flags,
        );
        errdefer device.freeMemory(memory);

        try device.bindBufferMemory(handle, memory, 0);

        return .{
            .device = device,
            .handle = handle,
            .memory = memory,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyBuffer(self.handle);
        self.device.freeMemory(self.memory);
    }

    pub fn copyFromBuffer(
        self: *Self,
        queue: c.VkQueue,
        queue_family_index: u32,
        src_buffer: c.VkBuffer,
        size: c.VkDeviceSize,
    ) !void {
        std.debug.assert(src_buffer != null);

        var command_buffer = try vk.CommandBuffers.init(
            self.device,
            1,
            queue_family_index,
        );
        defer command_buffer.deinit();

        try command_buffer.begin(0, true);

        const copy_region = std.mem.zeroInit(
            c.VkBufferCopy,
            .{
                .srcOffset = 0,
                .dstOffset = 0,
                .size = size,
            },
        );
        command_buffer.copyBuffer(
            0,
            src_buffer,
            self.handle,
            1,
            &copy_region,
        );

        try command_buffer.end(0);

        const submit_info = std.mem.zeroInit(
            c.VkSubmitInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .commandBufferCount = 1,
                .pCommandBuffers = &command_buffer.handles[0],
            },
        );
        try self.device.queueSubmit(
            queue,
            1,
            &submit_info,
            null,
        );

        try self.device.queueWaitIdle(queue);
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
