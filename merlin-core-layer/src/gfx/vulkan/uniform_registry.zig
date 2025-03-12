const std = @import("std");

const c = @import("../../c.zig").c;
const utils = @import("../../utils.zig");
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const UniformBufferEntry = struct {
    name: []const u8,
    buffer: [vk.MaxFramesInFlight]vk.uniform_buffer.UniformBuffer,
    buffer_count: u32,
    buffer_size: u32,
    ref_count: u32,
};

const UniformCombinedSamplerEntry = struct {
    name: []const u8,
    texture: ?gfx.TextureHandle,
    ref_count: u32,
};

const UniformEntry = union(gfx.DescriptorBindType) {
    uniform: UniformBufferEntry,
    combined_sampler: UniformCombinedSamplerEntry,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var allocator: std.mem.Allocator = undefined;
var name_map: std.StringHashMap(gfx.UniformHandle) = undefined;
var entries: [gfx.MaxUniformHandles]UniformEntry = undefined;
var handles: utils.HandlePool(gfx.UniformHandle, gfx.MaxUniformHandles) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(allocator_: std.mem.Allocator) !void {
    allocator = allocator_;
    name_map = .init(allocator);
    handles = .init();
}

pub fn deinit() void {
    // TODO: check for memory leaks
    name_map.deinit();
    handles.deinit();
}

pub fn createBuffer(name: []const u8, size: u32) !gfx.UniformHandle {
    const existing_handle = name_map.get(name);
    if (existing_handle) |value| {
        entries[value].uniform.ref_count += 1;
        return value;
    }

    const name_copy = try allocator.dupe(u8, name);
    errdefer allocator.free(name_copy);

    const handle = try handles.alloc();
    errdefer handles.free(handle);

    try name_map.put(name_copy, handle);
    errdefer _ = name_map.remove(name_copy);

    var buffer_count: u32 = 0;
    var buffer: [vk.MaxFramesInFlight]vk.uniform_buffer.UniformBuffer = undefined;

    errdefer {
        for (0..buffer_count) |i| {
            vk.uniform_buffer.destroy(&buffer[i]);
        }
    }
    inline for (0..vk.MaxFramesInFlight) |i| {
        buffer[i] = try vk.uniform_buffer.create(size);
        buffer_count += 1;
    }

    entries[handle] = UniformEntry{
        .uniform = UniformBufferEntry{
            .name = name_copy,
            .buffer = buffer,
            .buffer_count = buffer_count,
            .buffer_size = size,
            .ref_count = 1,
        },
    };

    vk.log.debug("Created uniform buffer:", .{});
    vk.log.debug("  - Name: {s}", .{name});
    vk.log.debug("  - Size: {s}", .{std.fmt.fmtIntSizeDec(size)});

    return handle;
}

pub fn updateBuffer(
    handle: gfx.UniformHandle,
    frame_index: u32,
    data: []const u8,
) !void {
    const entry = &entries[handle];
    switch (entry.*) {
        .uniform => {
            var uniform = &entry.uniform;
            std.debug.assert(frame_index < uniform.buffer_count);
            uniform.buffer[frame_index].update(data);
        },
        else => {
            vk.log.err("Uniform handle is not a buffer", .{});
            return error.UniformHandleIsNotABuffer;
        },
    }
}

pub inline fn getBuffer(handle: gfx.UniformHandle, index: u32) c.VkBuffer {
    return entries[handle].uniform.buffer[index].buffer.handle;
}

pub inline fn getBufferSize(handle: gfx.UniformHandle) u32 {
    return entries[handle].uniform.buffer_size;
}

pub fn createCombinedSampler(name: []const u8) !gfx.UniformHandle {
    const existing_handle = name_map.get(name);
    if (existing_handle) |value| {
        entries[value].combined_sampler.ref_count += 1;
        return value;
    }

    const name_copy = try allocator.dupe(u8, name);
    errdefer allocator.free(name_copy);

    const handle = try handles.alloc();
    errdefer handles.free(handle);

    try name_map.put(name_copy, handle);
    errdefer _ = name_map.remove(name_copy);

    entries[handle] = UniformEntry{
        .combined_sampler = UniformCombinedSamplerEntry{
            .name = name_copy,
            .texture = null,
            .ref_count = 1,
        },
    };

    vk.log.debug("Created combined sampler:", .{});
    vk.log.debug("  - Name: {s}", .{name});

    return handle;
}

pub fn updateCombinedSampler(
    handle: gfx.UniformHandle,
    texture: gfx.TextureHandle,
) !void {
    const entry = &entries[handle];
    switch (entry.*) {
        .combined_sampler => {
            entry.combined_sampler.texture = texture;
        },
        else => {
            vk.log.err("Uniform handle is not a combined sampler", .{});
            return error.UniformHandleIsNotACombinedSampler;
        },
    }
}

pub inline fn getCombinedSamplerTexture(handle: gfx.UniformHandle) ?gfx.TextureHandle {
    return entries[handle].combined_sampler.texture;
}

pub fn destroy(handle: gfx.UniformHandle) void {
    switch (entries[handle]) {
        .uniform => |*uniform| {
            std.debug.assert(uniform.ref_count > 0);

            uniform.ref_count -= 1;

            if (entries[handle].uniform.ref_count == 0) {
                vk.log.debug("Destroyed uniform buffer:", .{});
                vk.log.debug("  - Name: {s}", .{uniform.name});

                _ = name_map.remove(uniform.name);
                allocator.free(uniform.name);

                for (0..uniform.buffer_count) |i| {
                    vk.uniform_buffer.destroy(&uniform.buffer[i]);
                }

                handles.free(handle);
            }
        },
        .combined_sampler => |*combined_sampler| {
            std.debug.assert(combined_sampler.ref_count > 0);

            combined_sampler.ref_count -= 1;

            if (entries[handle].combined_sampler.ref_count == 0) {
                vk.log.debug("Destroyed combined sampler:", .{});
                vk.log.debug("  - Name: {s}", .{combined_sampler.name});

                _ = name_map.remove(combined_sampler.name);
                allocator.free(combined_sampler.name);

                handles.free(handle);
            }
        },
    }
}
