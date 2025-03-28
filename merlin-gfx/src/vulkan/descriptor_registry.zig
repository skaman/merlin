const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const UniformBufferEntry = struct {
    buffer: vk.uniform_buffer.UniformBuffer,
    buffer_size: u32,
    ref_count: u32,
};

const CombinedSamplerEntry = struct {
    texture: ?gfx.TextureHandle,
    ref_count: u32,
};

const Entry = union(types.DescriptorBindType) {
    uniform: UniformBufferEntry,
    combined_sampler: CombinedSamplerEntry,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var name_map: std.StringHashMap(gfx.UniformHandle) = undefined;
var entries: [gfx.MaxUniformHandles]?Entry = undefined;
var handles: utils.HandlePool(gfx.UniformHandle, gfx.MaxUniformHandles) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() !void {
    name_map = .init(vk.gpa);
    handles = .init();
    entries = std.mem.zeroes([gfx.MaxUniformHandles]?Entry);
}

pub fn deinit() void {
    // TODO: check for memory leaks

    var name_map_it = name_map.iterator();
    while (name_map_it.next()) |entry| {
        vk.gpa.free(entry.key_ptr.*);
    }

    name_map.deinit();
    handles.deinit();
}

pub fn registerName(name: []const u8) !gfx.UniformHandle {
    const existing_handle = name_map.get(name);
    if (existing_handle) |value| {
        return value;
    }

    const name_copy = try vk.gpa.dupe(u8, name);
    errdefer vk.gpa.free(name_copy);

    const handle = try handles.alloc();
    errdefer handles.free(handle);

    try name_map.put(name_copy, handle);
    errdefer _ = name_map.remove(name_copy);

    return handle;
}

pub fn createBuffer(name: []const u8, size: u32) !gfx.UniformHandle {
    const handle = try registerName(name);
    if (entries[handle] != null) {
        std.debug.assert(entries[handle].? == .uniform);
        entries[handle].?.uniform.ref_count += 1;
        return handle;
    }

    const buffer = try vk.uniform_buffer.create(size);
    errdefer vk.uniform_buffer.destroy(&buffer);

    entries[handle] = Entry{
        .uniform = UniformBufferEntry{
            .buffer = buffer,
            .buffer_size = size,
            .ref_count = 1,
        },
    };

    vk.log.debug("Created uniform buffer:", .{});
    vk.log.debug("  - Name: {s}", .{name});
    vk.log.debug("  - Size: {s}", .{std.fmt.fmtIntSizeDec(size)});

    return handle;
}

pub fn updateBuffer(handle: gfx.UniformHandle, data: []const u8) !void {
    std.debug.assert(entries[handle] != null);
    std.debug.assert(entries[handle].? == .uniform);

    const uniform = &entries[handle].?.uniform;
    std.debug.assert(data.len <= uniform.buffer_size);

    uniform.buffer.update(data);
}

pub inline fn getBuffer(handle: gfx.UniformHandle) c.VkBuffer {
    std.debug.assert(entries[handle] != null);
    std.debug.assert(entries[handle].? == .uniform);

    return entries[handle].?.uniform.buffer.buffer.handle;
}

pub inline fn getBufferSize(handle: gfx.UniformHandle) u32 {
    std.debug.assert(entries[handle] != null);
    std.debug.assert(entries[handle].? == .uniform);

    return entries[handle].?.uniform.buffer_size;
}

pub fn createCombinedSampler(name: []const u8) !gfx.UniformHandle {
    const handle = try registerName(name);
    if (entries[handle] != null) {
        std.debug.assert(entries[handle].? == .combined_sampler);
        entries[handle].?.combined_sampler.ref_count += 1;
        return handle;
    }

    entries[handle] = Entry{
        .combined_sampler = CombinedSamplerEntry{
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
    std.debug.assert(entries[handle] != null);
    std.debug.assert(entries[handle].? == .combined_sampler);

    const combined_sampler = &entries[handle].?.combined_sampler;
    combined_sampler.texture = texture;
}

pub inline fn getCombinedSamplerTexture(handle: gfx.UniformHandle) ?gfx.TextureHandle {
    std.debug.assert(entries[handle] != null);
    std.debug.assert(entries[handle].? == .combined_sampler);

    return entries[handle].?.combined_sampler.texture;
}

pub fn destroy(handle: gfx.UniformHandle) void {
    std.debug.assert(entries[handle] != null);

    switch (entries[handle].?) {
        .uniform => |*uniform| {
            std.debug.assert(uniform.ref_count > 0);

            uniform.ref_count -= 1;

            if (uniform.ref_count == 0) {
                vk.uniform_buffer.destroy(&uniform.buffer);
                handles.free(handle);
                entries[handle] = null;
            }
        },
        .combined_sampler => |*combined_sampler| {
            std.debug.assert(combined_sampler.ref_count > 0);

            combined_sampler.ref_count -= 1;

            if (combined_sampler.ref_count == 0) {
                handles.free(handle);
                entries[handle] = null;
            }
        },
    }
}
