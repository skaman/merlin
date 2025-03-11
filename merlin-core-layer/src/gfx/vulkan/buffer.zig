const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Buffer = struct {
    const Self = @This();

    handle: c.VkBuffer,
    memory: c.VkDeviceMemory,

    pub fn init(
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
        try vk.device.createBuffer(
            &buffer_info,
            &handle,
        );
        errdefer vk.device.destroyBuffer(handle);

        var requirements: c.VkMemoryRequirements = undefined;
        vk.device.getBufferMemoryRequirements(handle, &requirements);

        const memory = try allocateMemory(
            &requirements,
            property_flags,
        );
        errdefer vk.device.freeMemory(memory);

        try vk.device.bindBufferMemory(handle, memory, 0);

        return .{
            .handle = handle,
            .memory = memory,
        };
    }

    pub fn deinit(self: *Self) void {
        vk.device.destroyBuffer(self.handle);
        vk.device.freeMemory(self.memory);
    }

    pub fn copyFromBuffer(
        self: *Self,
        command_pool: c.VkCommandPool,
        queue: c.VkQueue,
        src_buffer: c.VkBuffer,
        size: c.VkDeviceSize,
    ) !void {
        std.debug.assert(src_buffer != null);

        var command_buffer = try vk.command_buffers.create(
            command_pool,
            1,
        );
        defer vk.command_buffers.destroy(&command_buffer);

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
        try vk.device.queueSubmit(
            queue,
            1,
            &submit_info,
            null,
        );

        try vk.device.queueWaitIdle(queue);
    }

    fn findMemoryTypeIndex(
        memory_type_bits: u32,
        property_flags: c.VkMemoryPropertyFlags,
    ) !u32 {
        var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
        vk.instance.getPhysicalDeviceMemoryProperties(
            vk.device.physical_device,
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
        requirements: *c.VkMemoryRequirements,
        property_flags: c.VkMemoryPropertyFlags,
    ) !c.VkDeviceMemory {
        const memory_type_index = try findMemoryTypeIndex(
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
        try vk.device.allocateMemory(
            &allocate_info,
            &memory,
        );
        return memory;
    }
};
