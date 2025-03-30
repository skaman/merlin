const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const UniformBuffer = struct {
    buffer: vk.buffer.Buffer,
    mapped_data: [*c]u8,
    mapped_data_size: u32,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var uniform_buffers: [gfx.MaxUniformBufferHandles]UniformBuffer = undefined;
var uniform_buffer_handles: utils.HandlePool(gfx.UniformBufferHandle, gfx.MaxUniformBufferHandles) = undefined;

var uniform_buffers_to_destroy: [gfx.MaxUniformBufferHandles]UniformBuffer = undefined;
var uniform_buffers_to_destroy_count: u32 = 0;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    uniform_buffer_handles = .init();
    uniform_buffers_to_destroy_count = 0;
}

pub fn deinit() void {
    uniform_buffer_handles.deinit();
}

pub fn create(size: u32) !gfx.UniformBufferHandle {
    var uniform_buffer = try vk.buffer.create(
        size,
        c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    errdefer vk.buffer.destroy(&uniform_buffer);

    var mapped_data: [*c]u8 = undefined;
    try vk.device.mapMemory(
        uniform_buffer.memory,
        0,
        size,
        0,
        @ptrCast(&mapped_data),
    );
    errdefer vk.device.unmapMemory(uniform_buffer.memory);

    const handle = try uniform_buffer_handles.alloc();
    errdefer uniform_buffer_handles.free(handle);

    uniform_buffers[handle] = .{
        .buffer = uniform_buffer,
        .mapped_data = mapped_data,
        .mapped_data_size = size,
    };

    vk.log.debug("Created uniform buffer:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroy(handle: gfx.UniformBufferHandle) void {
    uniform_buffers_to_destroy[uniform_buffers_to_destroy_count] = uniform_buffers[handle];
    uniform_buffers_to_destroy_count += 1;

    uniform_buffer_handles.free(handle);

    vk.log.debug("Destroyed uniform buffer with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..uniform_buffers_to_destroy_count) |i| {
        vk.device.unmapMemory(uniform_buffers_to_destroy[i].buffer.memory);
        vk.buffer.destroy(&uniform_buffers_to_destroy[i].buffer);
    }
    uniform_buffers_to_destroy_count = 0;
}

pub inline fn update(handle: gfx.UniformBufferHandle, data: []const u8, offset: u32) void {
    std.debug.assert(data.len <= uniform_buffers[handle].mapped_data_size);
    @memcpy(uniform_buffers[handle].mapped_data[offset .. data.len + offset], data);
}

pub inline fn buffer(handle: gfx.VertexBufferHandle) c.VkBuffer {
    return uniform_buffers[handle].buffer.handle;
}
