const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const PipelineLayout = struct {
    layout: types.VertexLayout,
    ref_count: u32,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _pipeline_layouts_map: std.AutoHashMap(
    types.VertexLayout,
    gfx.PipelineLayoutHandle,
) = undefined;
var _pipeline_to_destroy: std.ArrayList(*PipelineLayout) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _pipeline_layouts_map = .init(vk.gpa);
    errdefer _pipeline_layouts_map.deinit();

    _pipeline_to_destroy = .init(vk.gpa);
    errdefer _pipeline_to_destroy.deinit();
}

pub fn deinit() void {
    _pipeline_to_destroy.deinit();
    _pipeline_layouts_map.deinit();
}

pub fn create(vertex_layout: types.VertexLayout) !gfx.PipelineLayoutHandle {
    var pipeline_layout_handle = _pipeline_layouts_map.get(vertex_layout);
    if (pipeline_layout_handle) |handle| {
        var pipeline_layout = pipelineLayoutFromHandle(handle);
        pipeline_layout.ref_count += 1;
        return handle;
    }

    const pipeline_layout = try vk.gpa.create(PipelineLayout);
    errdefer vk.gpa.destroy(pipeline_layout);

    pipeline_layout.* = .{
        .layout = vertex_layout,
        .ref_count = 1,
    };

    pipeline_layout_handle = .{ .handle = @ptrCast(pipeline_layout) };

    try _pipeline_layouts_map.put(vertex_layout, pipeline_layout_handle.?);
    errdefer _ = _pipeline_layouts_map.remove(vertex_layout);

    return pipeline_layout_handle.?;
}

pub fn destroy(handle: gfx.PipelineLayoutHandle) void {
    var pipeline_layout = pipelineLayoutFromHandle(handle);
    if (pipeline_layout.ref_count == 1) {
        _ = _pipeline_layouts_map.remove(pipeline_layout.layout);
        vk.gpa.destroy(pipeline_layout);
    } else {
        pipeline_layout.ref_count -= 1;
    }
}

pub inline fn pipelineLayoutFromHandle(handle: gfx.PipelineLayoutHandle) *PipelineLayout {
    return @ptrCast(@alignCast(handle.handle));
}
