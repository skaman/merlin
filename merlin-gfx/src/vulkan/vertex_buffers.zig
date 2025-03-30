const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const VertexBuffer = struct {
    buffer: vk.buffer.Buffer,
    layout: gfx.PipelineLayoutHandle,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var vertex_buffers: utils.HandleArray(
    gfx.VertexBufferHandle,
    VertexBuffer,
    gfx.MaxVertexBufferHandles,
) = undefined;

var vertex_buffer_handles: utils.HandlePool(
    gfx.VertexBufferHandle,
    gfx.MaxVertexBufferHandles,
) = undefined;

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
    loader: utils.loaders.VertexBufferLoader,
) !gfx.VertexBufferHandle {
    var local_loader = loader;
    try local_loader.open();
    defer local_loader.close();

    const buffer_layout = try local_loader.readLayout(vk.gpa);
    const data_size = try local_loader.readDataSize();

    const layout_handle = try vk.pipeline_layouts.create(buffer_layout);
    errdefer vk.pipeline_layouts.destroy(layout_handle);

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

    var vertex_buffer = try vk.buffer.create(
        @intCast(data_size),
        c.VK_BUFFER_USAGE_TRANSFER_DST_BIT | c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );
    errdefer vk.buffer.destroy(&vertex_buffer);

    try vk.buffer.copyBuffer(
        command_pool,
        queue,
        staging_buffer.handle,
        vertex_buffer.handle,
        @intCast(data_size),
    );

    const handle = try vertex_buffer_handles.create();
    errdefer vertex_buffer_handles.destroy(handle);

    vertex_buffers.setValue(
        handle,
        .{
            .buffer = vertex_buffer,
            .layout = layout_handle,
        },
    );

    vk.log.debug("Created vertex buffer:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroy(handle: gfx.VertexBufferHandle) void {
    vertex_buffers_to_destroy[vertex_buffers_to_destroy_count] = vertex_buffers.value(handle);
    vertex_buffers_to_destroy_count += 1;

    vertex_buffer_handles.destroy(handle);

    vk.log.debug("Destroyed vertex buffer with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..vertex_buffers_to_destroy_count) |i| {
        vk.buffer.destroy(&vertex_buffers_to_destroy[i].buffer);
        vk.pipeline_layouts.destroy(vertex_buffers_to_destroy[i].layout);
    }
    vertex_buffers_to_destroy_count = 0;
}

pub inline fn buffer(handle: gfx.VertexBufferHandle) c.VkBuffer {
    const vertex_buffer = vertex_buffers.valuePtr(handle);
    return vertex_buffer.buffer.handle;
}

pub inline fn layout(handle: gfx.VertexBufferHandle) gfx.PipelineLayoutHandle {
    const vertex_buffer = vertex_buffers.valuePtr(handle);
    return vertex_buffer.layout;
}
