const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Globals
// *********************************************************************************************

var name_map: std.StringHashMap(gfx.UniformHandle) = undefined;
var handles: utils.HandlePool(gfx.UniformHandle, gfx.MaxUniformHandles) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() !void {
    name_map = .init(vk.gpa);
    handles = .init();
}

pub fn deinit() void {
    var name_map_it = name_map.iterator();
    while (name_map_it.next()) |entry| {
        vk.gpa.free(entry.key_ptr.*);
    }

    handles.clear();

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

    const handle = handles.create();
    errdefer handles.destroy(handle);

    try name_map.put(name_copy, handle);
    errdefer _ = name_map.remove(name_copy);

    return handle;
}
