const std = @import("std");

const gfx = @import("merlin_gfx");
const utils = @import("merlin_utils");
const asset_types = utils.asset_types;

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const MeshInfo = struct {
    pipeline_handle: gfx.PipelineLayoutHandle,
    buffer_handle: gfx.BufferHandle,
    vertex_buffer_offset: u32,
    index_buffer_offset: u32,
    data: asset_types.MeshData,
};

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn readMesh(allocator: std.mem.Allocator, reader: std.io.AnyReader) !asset_types.MeshData {
    try utils.Serializer.checkHeader(
        reader,
        asset_types.MeshMagic,
        asset_types.MeshVersion,
    );
    return try utils.Serializer.read(
        asset_types.MeshData,
        allocator,
        reader,
    );
}

pub fn loadMesh(allocator: std.mem.Allocator, reader: std.io.AnyReader) !MeshInfo {
    const mesh_data = try readMesh(allocator, reader);
    const data_size = mesh_data.vertices_data_size + mesh_data.indices_data_size;

    const pipeline_handle = try gfx.createPipelineLayout(
        mesh_data.vertex_layout,
    );
    errdefer gfx.destroyPipelineLayout(pipeline_handle);

    const buffer_handle = try gfx.createBuffer(
        data_size,
        .{
            .index = true,
            .vertex = true,
        },
        .device,
    );
    errdefer gfx.destroyBuffer(buffer_handle);

    try gfx.updateBuffer(buffer_handle, reader, 0, data_size);

    return MeshInfo{
        .pipeline_handle = pipeline_handle,
        .buffer_handle = buffer_handle,
        .vertex_buffer_offset = 0,
        .index_buffer_offset = mesh_data.vertices_data_size,
        .data = mesh_data,
    };
}
