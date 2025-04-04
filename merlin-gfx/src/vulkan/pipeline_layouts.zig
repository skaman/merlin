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

var pipeline_layouts: utils.HandleArray(
    gfx.PipelineLayoutHandle,
    PipelineLayout,
    gfx.MaxPipelineLayoutHandles,
) = undefined;

var pipeline_layout_handles: utils.HandlePool(
    gfx.PipelineLayoutHandle,
    gfx.MaxPipelineLayoutHandles,
) = undefined;

var pipeline_layouts_map: std.AutoHashMap(
    types.VertexLayout,
    gfx.PipelineLayoutHandle,
) = undefined;

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
        var pipeline_layout = pipeline_layouts.valuePtr(handle);
        pipeline_layout.ref_count += 1;
        return handle;
    }

    pipeline_layout_handle = pipeline_layout_handles.create();
    errdefer pipeline_layout_handles.destroy(pipeline_layout_handle.?);

    pipeline_layouts.setValue(
        pipeline_layout_handle.?,
        .{
            .layout = vertex_layout,
            .ref_count = 1,
        },
    );

    try pipeline_layouts_map.put(vertex_layout, pipeline_layout_handle.?);
    errdefer _ = pipeline_layouts_map.remove(vertex_layout);

    return pipeline_layout_handle.?;
}

pub fn destroy(handle: gfx.PipelineLayoutHandle) void {
    const pipeline_layout = pipeline_layouts.valuePtr(handle);
    if (pipeline_layout.ref_count == 1) {
        _ = pipeline_layouts_map.remove(pipeline_layout.layout);
        pipeline_layout_handles.destroy(handle);
    } else {
        pipeline_layout.ref_count -= 1;
    }
}

pub inline fn layout(handle: gfx.PipelineLayoutHandle) *const types.VertexLayout {
    const pipeline_layout = pipeline_layouts.valuePtr(handle);
    return &pipeline_layout.layout;
}
