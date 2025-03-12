const std = @import("std");

const c = @import("../../c.zig").c;
const utils = @import("../../utils.zig");
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const VertexBuffer = struct {
    buffer: vk.buffer.Buffer,
    layout: gfx.VertexLayout,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var vertex_buffers: [gfx.MaxVertexBufferHandles]VertexBuffer = undefined;
var vertex_buffer_handles: utils.HandlePool(gfx.VertexBufferHandle, gfx.MaxVertexBufferHandles) = undefined;

var vertex_buffers_to_destroy: [gfx.MaxVertexBufferHandles]VertexBuffer = undefined;
var vertex_buffers_to_destroy_count: u32 = 0;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    vertex_buffer_handles = .init();
    vertex_buffers_to_destroy_count = 0;
}

pub fn deinit() void {
    vertex_buffer_handles.deinit();
}

pub fn create(
    command_pool: c.VkCommandPool,
    queue: c.VkQueue,
    layout: gfx.VertexLayout,
    data: []const u8,
) !gfx.VertexBufferHandle {
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
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
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

    const handle = try vertex_buffer_handles.alloc();
    errdefer vertex_buffer_handles.free(handle);

    vertex_buffers[handle] = .{
        .buffer = buffer,
        .layout = layout,
    };

    vk.log.debug("Created vertex buffer:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroy(handle: gfx.VertexBufferHandle) void {
    vertex_buffers_to_destroy[vertex_buffers_to_destroy_count] = vertex_buffers[handle];
    vertex_buffers_to_destroy_count += 1;

    vertex_buffer_handles.free(handle);

    vk.log.debug("Destroyed vertex buffer with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..vertex_buffers_to_destroy_count) |i| {
        vk.buffer.destroy(&vertex_buffers_to_destroy[i].buffer);
    }
    vertex_buffers_to_destroy_count = 0;
}

pub inline fn getBuffer(handle: gfx.VertexBufferHandle) c.VkBuffer {
    return vertex_buffers[handle].buffer.handle;
}

pub inline fn getLayout(handle: gfx.VertexBufferHandle) *gfx.VertexLayout {
    return &vertex_buffers[handle].layout;
}
