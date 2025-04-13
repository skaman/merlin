const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Buffer = struct {
    handle: c.VkBuffer,
    memory: c.VkDeviceMemory,
    property_flags: c.VkMemoryPropertyFlags,
    mapped_data: [*c]u8,
    mapped_data_size: u32,
    debug_name: ?[]const u8,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var buffers: utils.HandleArray(
    gfx.BufferHandle,
    Buffer,
    gfx.MaxBufferHandles,
) = undefined;

var buffer_handles: utils.HandlePool(
    gfx.BufferHandle,
    gfx.MaxBufferHandles,
) = undefined;

var buffers_to_destroy: [gfx.MaxBufferHandles]Buffer = undefined;
var buffers_to_destroy_count: u32 = 0;

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

fn copyBuffer(
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
    src_buffer: c.VkBuffer,
    dst_buffer: c.VkBuffer,
    size: c.VkDeviceSize,
    src_offset: u32,
    dst_offset: u32,
    debug_label: ?[]const u8,
) !void {
    std.debug.assert(src_buffer != null);

    const command_buffer =
        try vk.command_buffers.beginSingleTimeCommands(command_pool);
    defer vk.command_buffers.endSingleTimeCommands(
        command_pool,
        command_buffer,
        queue,
    );

    vk.debug.beginCommandBufferLabel(
        command_buffer,
        try std.fmt.allocPrint(
            vk.arena,
            "Copy buffer {s}",
            .{
                if (debug_label) |label|
                    label
                else
                    "-",
            },
        ),
        types.Colors.DarkSlateBlue,
    );
    defer vk.debug.endCommandBufferLabel(command_buffer);

    const copy_region = std.mem.zeroInit(
        c.VkBufferCopy,
        .{
            .srcOffset = src_offset,
            .dstOffset = dst_offset,
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

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    buffer_handles = .init();
    buffers_to_destroy_count = 0;
}

pub fn deinit() void {
    buffer_handles.deinit();
}

pub fn create(
    size: u32,
    usage: gfx.BufferUsage,
    location: gfx.BufferLocation,
    options: gfx.BufferOptions,
) !gfx.BufferHandle {
    var buffer_usage_flags: c.VkBufferUsageFlags = 0;
    if (usage.vertex) buffer_usage_flags |= c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (usage.index) buffer_usage_flags |= c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (usage.uniform) buffer_usage_flags |= c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;

    const handle = buffer_handles.create();
    errdefer buffer_handles.destroy(handle);

    var result_buffer: Buffer = undefined;
    switch (location) {
        .device => {
            result_buffer = try createBuffer(
                @intCast(size),
                buffer_usage_flags | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
                options.debug_name,
            );
            errdefer destroyBuffer(&result_buffer);

            buffers.setValue(handle, result_buffer);
        },
        .host => {
            result_buffer = try createBuffer(
                @intCast(size),
                buffer_usage_flags,
                c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
                options.debug_name,
            );
            errdefer destroyBuffer(&result_buffer);

            var mapped_data: [*c]u8 = undefined;
            try vk.device.mapMemory(
                result_buffer.memory,
                0,
                size,
                0,
                @ptrCast(&mapped_data),
            );
            errdefer vk.device.unmapMemory(result_buffer.memory);

            result_buffer.mapped_data = mapped_data;
            result_buffer.mapped_data_size = size;

            buffers.setValue(handle, result_buffer);
        },
    }

    vk.log.debug("Created buffer:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});
    if (options.debug_name) |name| {
        try vk.debug.setObjectName(c.VK_OBJECT_TYPE_BUFFER, result_buffer.handle, name);
        vk.log.debug("  - Name: {s}", .{name});
    }
    vk.log.debug("  - Size: {s}", .{std.fmt.fmtIntSizeDec(size)});
    vk.log.debug("  - Usage uniform: {}", .{usage.uniform});
    vk.log.debug("  - Usage vertex: {}", .{usage.vertex});
    vk.log.debug("  - Usage index: {}", .{usage.index});
    vk.log.debug("  - Location: {s}", .{location.name()});

    return handle;
}

pub fn destroy(handle: gfx.BufferHandle) void {
    buffers_to_destroy[buffers_to_destroy_count] = buffers.value(handle);
    buffers_to_destroy_count += 1;

    buffer_handles.destroy(handle);

    vk.log.debug("Destroyed buffer with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..buffers_to_destroy_count) |i| {
        if (buffers_to_destroy[i].property_flags & c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT != 0) {
            vk.device.unmapMemory(buffers_to_destroy[i].memory);
        }
        destroyBuffer(&buffers_to_destroy[i]);
    }
    buffers_to_destroy_count = 0;
}

pub inline fn buffer(handle: gfx.BufferHandle) c.VkBuffer {
    const buf = buffers.valuePtr(handle);
    return buf.handle;
}

pub fn update(
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
    handle: gfx.BufferHandle,
    reader: std.io.AnyReader,
    offset: u32,
    size: u32,
) !void {
    const buf = buffers.valuePtr(handle);
    if (buf.property_flags & c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT != 0) {
        _ = try reader.readAll(buf.mapped_data[offset .. size + offset]);
    } else {
        var staging_buffer = try createBuffer(
            @intCast(size),
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            buf.debug_name,
        );
        defer destroyBuffer(&staging_buffer);

        var mapped_data: [*c]u8 = undefined;
        try vk.device.mapMemory(
            staging_buffer.memory,
            0,
            @intCast(size),
            0,
            @ptrCast(&mapped_data),
        );
        defer vk.device.unmapMemory(staging_buffer.memory);

        _ = try reader.readAll(mapped_data[0..size]);

        try copyBuffer(
            command_pool,
            queue,
            staging_buffer.handle,
            buf.handle,
            @intCast(size),
            0,
            offset,
            buf.debug_name,
        );
    }
}

pub fn createBuffer(
    size: c.VkDeviceSize,
    usage: c.VkBufferUsageFlags,
    property_flags: c.VkMemoryPropertyFlags,
    debug_name: ?[]const u8,
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
        .property_flags = property_flags,
        .mapped_data = null,
        .mapped_data_size = 0,
        .debug_name = debug_name,
    };
}

pub fn destroyBuffer(buf: *Buffer) void {
    vk.device.destroyBuffer(buf.handle);
    vk.device.freeMemory(buf.memory);
}
