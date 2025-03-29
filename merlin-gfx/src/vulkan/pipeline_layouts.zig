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

var pipeline_layouts: [gfx.MaxPipelineLayoutHandles]PipelineLayout = undefined;
var pipeline_layout_handles: utils.HandlePool(gfx.PipelineLayoutHandle, gfx.MaxPipelineLayoutHandles) = undefined;
var pipeline_layouts_map: std.AutoHashMap(types.VertexLayout, gfx.PipelineLayoutHandle) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    pipeline_layout_handles = .init();
    pipeline_layouts_map = .init(vk.gpa);
}

pub fn deinit() void {
    pipeline_layouts_map.deinit();
    pipeline_layout_handles.deinit();
}

pub fn create(vertex_layout: types.VertexLayout) !gfx.PipelineLayoutHandle {
    var pipeline_layout_handle = pipeline_layouts_map.get(vertex_layout);
    if (pipeline_layout_handle) |handle| {
        pipeline_layouts[handle].ref_count += 1;
        return handle;
    }

    pipeline_layout_handle = try pipeline_layout_handles.alloc();
    errdefer pipeline_layout_handles.free(pipeline_layout_handle.?);

    pipeline_layouts[pipeline_layout_handle.?] = .{
        .layout = vertex_layout,
        .ref_count = 1,
    };

    try pipeline_layouts_map.put(vertex_layout, pipeline_layout_handle.?);
    errdefer _ = pipeline_layouts_map.remove(vertex_layout);

    return pipeline_layout_handle.?;
}

pub fn destroy(handle: gfx.PipelineLayoutHandle) void {
    if (pipeline_layouts[handle].ref_count == 1) {
        _ = pipeline_layouts_map.remove(pipeline_layouts[handle].layout);
        pipeline_layout_handles.free(handle);
    } else {
        pipeline_layouts[handle].ref_count -= 1;
    }
}

pub inline fn layout(handle: gfx.PipelineLayoutHandle) *const types.VertexLayout {
    return &pipeline_layouts[handle].layout;
}
