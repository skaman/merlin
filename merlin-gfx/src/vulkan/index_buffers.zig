const std = @import("std");

const utils = @import("merlin_utils");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const IndexBuffer = struct {
    buffer: vk.buffer.Buffer,
    index_type: gfx.IndexType,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var index_buffers: [gfx.MaxIndexBufferHandles]IndexBuffer = undefined;
var index_buffer_handles: utils.HandlePool(gfx.IndexBufferHandle, gfx.MaxIndexBufferHandles) = undefined;

var index_buffers_to_destroy: [gfx.MaxIndexBufferHandles]IndexBuffer = undefined;
var index_buffers_to_destroy_count: u32 = 0;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    index_buffer_handles = .init();
    index_buffers_to_destroy_count = 0;
}

pub fn deinit() void {
    index_buffer_handles.deinit();
}

pub fn create(
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
    data: []const u8,
    index_type: gfx.IndexType,
) !gfx.IndexBufferHandle {
    std.debug.assert(queue != null);
    std.debug.assert(data.len > 0);

    var staging_buffer = try vk.buffer.create(
        @intCast(data.len),
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    defer vk.buffer.destroy(&staging_buffer);

    var mapped_data: [*c]u8 = undefined;
    try vk.device.mapMemory(
        staging_buffer.memory,
        0,
        @intCast(data.len),
        0,
        @ptrCast(&mapped_data),
    );
    defer vk.device.unmapMemory(staging_buffer.memory);

    @memcpy(mapped_data[0..data.len], data);

    var buffer = try vk.buffer.create(
        @intCast(data.len),
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );
    errdefer vk.buffer.destroy(&buffer);

    try vk.buffer.copyBuffer(
        command_pool,
        queue,
        staging_buffer.handle,
        buffer.handle,
        @intCast(data.len),
    );

    const handle = try index_buffer_handles.alloc();
    errdefer index_buffer_handles.free(handle);

    index_buffers[handle] = .{
        .buffer = buffer,
        .index_type = index_type,
    };

    vk.log.debug("Created index buffer:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroy(handle: gfx.IndexBufferHandle) void {
    index_buffers_to_destroy[index_buffers_to_destroy_count] = index_buffers[handle];
    index_buffers_to_destroy_count += 1;

    index_buffer_handles.free(handle);

    vk.log.debug("Destroyed index buffer with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..index_buffers_to_destroy_count) |i| {
        vk.buffer.destroy(&index_buffers_to_destroy[i].buffer);
    }
    index_buffers_to_destroy_count = 0;
}

pub inline fn getBuffer(handle: gfx.IndexBufferHandle) c.VkBuffer {
    return index_buffers[handle].buffer.handle;
}

pub inline fn getIndexType(handle: gfx.IndexBufferHandle) gfx.IndexType {
    return index_buffers[handle].index_type;
}
