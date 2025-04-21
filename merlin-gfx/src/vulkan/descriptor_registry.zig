const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _name_map: std.StringHashMap(gfx.UniformHandle) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() !void {
    _name_map = .init(vk.gpa);
}

pub fn deinit() void {
    var name_map_it = _name_map.iterator();
    while (name_map_it.next()) |entry| {
        vk.gpa.free(entry.key_ptr.*);
    }

    _name_map.deinit();
}

pub fn registerName(name: []const u8) !gfx.UniformHandle {
    const existing_handle = _name_map.get(name);
    if (existing_handle) |value| {
        return value;
    }

    const name_copy = try vk.gpa.dupe(u8, name);
    errdefer vk.gpa.free(name_copy);

    const handle = gfx.UniformHandle{
        .handle = @ptrCast(name_copy.ptr),
    };

    try _name_map.put(name_copy, handle);

    return handle;
}
