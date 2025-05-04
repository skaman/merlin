const std = @import("std");

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
    if (size == 0) {
        return null;
    }

    const totale_size = HeaderSize + size;

    const ptr = vk.gpa.rawAlloc(
        totale_size,
        .fromByteUnits(alignment),
        @returnAddress(),
    );
    if (ptr == null) {
        vk.log.err(
            "Vulkan allocation: failed to allocate {d} bytes",
            .{size},
        );
        return null;
    }

    vulkan_memory_usage += size;

    const size_ptr: *usize = @ptrCast(@alignCast(ptr));
    const align_ptr: *usize = @ptrCast(@alignCast(ptr.? + HeaderAlignmentOffset));
    size_ptr.* = size;
    align_ptr.* = alignment;

    return ptr.? + HeaderSize;
}

pub fn vulkanReallocation(
    user_data: ?*anyopaque,
    original: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.c) ?*anyopaque {
    if (original == null) {
        return vulkanAllocation(
            user_data,
            size,
            alignment,
            allocation_scope,
        );
    }

    if (size == 0) {
        vulkanFree(user_data, original);
        return null;
    }

    const old_size = getSize(original);
    const old_alignment = getAlignment(original);

    if (alignment != old_alignment) {
        vk.log.err(
            "Vulkan reallocation: alignment mismatch: {d} != {d}",
            .{ alignment, old_alignment },
        );
        return null;
    }

    // TODO: add remap (remember to consider vulkan_memory_usage when remap)
    //vk.gpa.rawRemap(memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize)

    const result = vulkanAllocation(
        user_data,
        size,
        alignment,
        allocation_scope,
    );
    if (result != null) {
        const copy_size = @min(size, old_size);
        const dest_ptr: [*c]u8 = @ptrCast(@alignCast(result));
        const src_ptr: [*c]u8 = @ptrCast(@alignCast(original));
        @memcpy(dest_ptr[0..copy_size], src_ptr[0..copy_size]);

        vulkanFree(user_data, original);
    } else {
        vk.log.err(
            "Vulkan reallocation: failed to allocate {d} bytes",
            .{size},
        );
    }

    return result;
}

pub fn vulkanFree(
    _: ?*anyopaque,
    memory: ?*anyopaque,
) callconv(.c) void {
    if (memory != null) {
        const size = getSize(memory);
        const alignment = getAlignment(memory);
        var ptr: [*c]u8 = @ptrCast(@alignCast(memory));
        ptr -= HeaderSize;
        vk.gpa.rawFree(ptr[0 .. size + HeaderSize], .fromByteUnits(alignment), @returnAddress());

        vulkan_memory_usage -= size;
    }
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
