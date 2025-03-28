const std = @import("std");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Buffer = struct {
    handle: c.VkBuffer,
    memory: c.VkDeviceMemory,
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn allocateMemory(
    requirements: *c.VkMemoryRequirements,
    property_flags: c.VkMemoryPropertyFlags,
) !c.VkDeviceMemory {
    const memory_type_index = try vk.findMemoryTypeIndex(
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

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn create(
    size: c.VkDeviceSize,
    usage: c.VkBufferUsageFlags,
    property_flags: c.VkMemoryPropertyFlags,
) !Buffer {
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

    return Buffer{
        .handle = handle,
        .memory = memory,
    };
}

pub fn destroy(buffer: *Buffer) void {
    vk.device.destroyBuffer(buffer.handle);
    vk.device.freeMemory(buffer.memory);
}

pub fn copyBuffer(
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
    src_buffer: c.VkBuffer,
    dst_buffer: c.VkBuffer,
    size: c.VkDeviceSize,
) !void {
    std.debug.assert(src_buffer != null);

    const command_buffer =
        try vk.command_buffers.beginSingleTimeCommands(command_pool);
    defer vk.command_buffers.endSingleTimeCommands(
        command_pool,
        command_buffer,
        queue,
    );

    const copy_region = std.mem.zeroInit(
        c.VkBufferCopy,
        .{
            .srcOffset = 0,
            .dstOffset = 0,
            .size = size,
        },
    );

    vk.device.cmdCopyBuffer(
        command_buffer,
        src_buffer,
        dst_buffer,
        1,
        &copy_region,
    );
}
