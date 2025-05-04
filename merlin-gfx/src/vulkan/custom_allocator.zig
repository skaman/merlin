const std = @import("std");

const utils = @import("merlin_utils");

const c = @import("../c.zig").c;
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Constants
// *********************************************************************************************

const HeaderSize = @sizeOf(usize) * 2;
const HeaderAlignmentOffset = @sizeOf(usize);

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var vulkan_memory_usage: usize = 0;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn getSize(memory: ?*anyopaque) usize {
    if (memory == null) return 0;

    const ptr: [*c]u8 = @ptrCast(@alignCast(memory));
    const size_ptr: *usize = @ptrCast(@alignCast(ptr - HeaderSize));
    return size_ptr.*;
}

fn getAlignment(memory: ?*anyopaque) usize {
    if (memory == null) return 0;

    const ptr: [*c]u8 = @ptrCast(@alignCast(memory));
    const alignment_ptr: *usize = @ptrCast(@alignCast(ptr - HeaderSize + HeaderAlignmentOffset));
    return alignment_ptr.*;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn vulkanAllocation(
    _: ?*anyopaque,
    size: usize,
    alignment: usize,
    _: c.VkSystemAllocationScope,
) callconv(.c) ?*anyopaque {
    const raw_allocator = utils.RawAllocator.init(vk.gpa);
    return raw_allocator.allocate(size, @intCast(alignment));
}

pub fn vulkanReallocation(
    _: ?*anyopaque,
    original: ?*anyopaque,
    size: usize,
    alignment: usize,
    _: c.VkSystemAllocationScope,
) callconv(.c) ?*anyopaque {
    const raw_allocator = utils.RawAllocator.init(vk.gpa);
    return raw_allocator.reallocate(
        @ptrCast(original),
        size,
        @intCast(alignment),
    );
}

pub fn vulkanFree(
    _: ?*anyopaque,
    memory: ?*anyopaque,
) callconv(.c) void {
    const raw_allocator = utils.RawAllocator.init(vk.gpa);
    raw_allocator.free(@ptrCast(memory));
}

pub fn vulkanInternalAllocation(
    _: ?*anyopaque,
    size: usize,
    _: c.VkInternalAllocationType,
    _: c.VkSystemAllocationScope,
) callconv(.c) void {
    vk.log.debug(
        "Vulkan internal allocation: {d} bytes",
        .{size},
    );
}

pub fn vulkanInternalFree(
    _: ?*anyopaque,
    size: usize,
    _: c.VkInternalAllocationType,
    _: c.VkSystemAllocationScope,
) callconv(.c) void {
    vk.log.debug(
        "Vulkan internal free: {d} bytes",
        .{size},
    );
}
