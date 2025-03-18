const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const IndexBuffer = struct {
    buffer: vk.buffer.Buffer,
    index_type: types.IndexType,
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
    loader: utils.loaders.IndexBufferLoader,
) !gfx.IndexBufferHandle {
    std.debug.assert(queue != null);

    var local_loader = loader;
    try local_loader.open();
    defer local_loader.close();

    const index_type = try local_loader.readIndexType();
    const data_size = try local_loader.readDataSize();

    var staging_buffer = try vk.buffer.create(
        @intCast(data_size),
        c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    defer vk.buffer.destroy(&staging_buffer);

    var mapped_data: [*c]u8 = undefined;
    try vk.device.mapMemory(
        staging_buffer.memory,
        0,
        @intCast(data_size),
        0,
        @ptrCast(&mapped_data),
    );
    defer vk.device.unmapMemory(staging_buffer.memory);

    try local_loader.readData(mapped_data[0..data_size]);

    var buffer = try vk.buffer.create(
        @intCast(data_size),
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );
    errdefer vk.buffer.destroy(&buffer);

    try vk.buffer.copyBuffer(
        command_pool,
        queue,
        staging_buffer.handle,
        buffer.handle,
        @intCast(data_size),
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

pub inline fn getIndexType(handle: gfx.IndexBufferHandle) types.IndexType {
    return index_buffers[handle].index_type;
}
