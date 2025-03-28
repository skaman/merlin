const std = @import("std");

const assets = @import("merlin_assets");
const gltf = @import("merlin_gltf");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Options = struct {
    attribute_normal: bool = true,
    attribute_tangent: bool = false,
    attribute_color: bool = false,
    attribute_weight: bool = false,
    attribute_tex_coord: bool = true,
};

pub const VertexBufferData = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    layout: gfx_types.VertexLayout,
    num_vertices: usize,

    pub fn deinit(self: *const VertexBufferData) void {
        self.allocator.free(self.data);
    }
};

pub const IndexBufferData = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    index_type: gfx_types.IndexType,
    num_indices: usize,

    pub fn deinit(self: *const IndexBufferData) void {
        self.allocator.free(self.data);
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn addVertexAttribute(
    vertex_layout: *gfx_types.VertexLayout,
    primitive: gltf.Primitive,
    attribute_type: gfx_types.VertexAttributeType,
) !void {
    const attribute = try primitive.attributeByType(attribute_type) orelse {
        std.log.err("Attribute not found: {s}\n", .{attribute_type.name()});
        return error.AttributeNotFound;
    };

    const accessor = attribute.accessor();

    vertex_layout.add(
        attribute_type,
        @intCast(try accessor.componentCount()),
        try accessor.componentType(),
        accessor.normalized(),
    );
}

fn calculateVertexLayout(
    primitive: gltf.Primitive,
    options: Options,
) !gfx_types.VertexLayout {
    var vertex_layout = gfx_types.VertexLayout.init();

    try addVertexAttribute(
        &vertex_layout,
        primitive,
        .position,
    );

    if (options.attribute_normal) {
        try addVertexAttribute(
            &vertex_layout,
            primitive,
            .normal,
        );
    }

    if (options.attribute_tangent) {
        try addVertexAttribute(
            &vertex_layout,
            primitive,
            .tangent,
        );
    }

    if (options.attribute_color) {
        try addVertexAttribute(
            &vertex_layout,
            primitive,
            .color_0,
        );
    }

    if (options.attribute_weight) {
        try addVertexAttribute(
            &vertex_layout,
            primitive,
            .weight,
        );
    }

    if (options.attribute_tex_coord) {
        try addVertexAttribute(
            &vertex_layout,
            primitive,
            .tex_coord_0,
        );
    }

    return vertex_layout;
}
fn createVertexBuffer(
    allocator: std.mem.Allocator,
    primitive: gltf.Primitive,
    vertex_layout: gfx_types.VertexLayout,
    num_vertices: usize,
) ![]const u8 {
    const vertex_data_size = num_vertices * vertex_layout.stride;
    const vertex_data = try allocator.alloc(u8, vertex_data_size);
    errdefer allocator.free(vertex_data);

    for (0..vertex_layout.attributes.len) |attribute_index| {
        const attribute = &vertex_layout.attributes[attribute_index];
        const attribute_type: gfx_types.VertexAttributeType = @enumFromInt(attribute_index);
        if (attribute.num == 0) continue;

        const gltf_attribute = try primitive.attributeByType(attribute_type) orelse
            return error.AttributeNotFound;
        const gltf_accessor = gltf_attribute.accessor();

        const input_data = gltf_accessor.data();
        const input_stride = gltf_accessor.stride();

        for (0..num_vertices) |vertex_index| {
            const input_offset = vertex_index * input_stride;
            const output_offset = vertex_index * vertex_layout.stride + vertex_layout.offsets[attribute_index];
            const stride = @min(input_stride, vertex_layout.stride);

            @memcpy(
                vertex_data[output_offset .. output_offset + stride],
                input_data[input_offset .. input_offset + stride],
            );
        }
    }

    return vertex_data;
}

fn createIndexBuffer(
    allocator: std.mem.Allocator,
    indices: gltf.Accessor,
    index_type: gfx_types.IndexType,
) ![]const u8 {
    const index_type_size = index_type.size();
    const index_data_size = indices.count() * index_type_size;
    const index_data = try allocator.alloc(u8, index_data_size);
    errdefer allocator.free(index_data);

    const input_data = indices.data();

    for (0..indices.count()) |index| {
        const input_offset = index * index_type_size;
        const output_offset = index * index_type_size;

        @memcpy(
            index_data[output_offset .. output_offset + index_type_size],
            input_data[input_offset .. input_offset + index_type_size],
        );
    }

    return index_data;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn convertVertexBuffer(
    allocator: std.mem.Allocator,
    source: gltf.Gltf,
    mesh_index: usize,
    primitive_index: usize,
    options: Options,
) !VertexBufferData {
    const mesh = source.mesh(mesh_index);
    const primitive = mesh.primitive(primitive_index);

    const position_attribute = try primitive.attributeByType(.position) orelse
        return error.AttributeNotFound;
    const num_vertices = position_attribute.accessor().count();

    const vertex_layout = try calculateVertexLayout(
        primitive,
        options,
    );

    const vertex_data = try createVertexBuffer(
        allocator,
        primitive,
        vertex_layout,
        num_vertices,
    );
    errdefer allocator.free(vertex_data);

    return .{
        .allocator = allocator,
        .data = vertex_data,
        .layout = vertex_layout,
        .num_vertices = num_vertices,
    };
}

pub fn convertIndexBuffer(
    allocator: std.mem.Allocator,
    source: gltf.Gltf,
    mesh_index: usize,
    primitive_index: usize,
) !IndexBufferData {
    const mesh = source.mesh(mesh_index);
    const primitive = mesh.primitive(primitive_index);

    const num_indices = primitive.indices().count();

    const indices = primitive.indices();
    const index_type: gfx_types.IndexType = switch (try indices.componentType()) {
        .u8 => .u8,
        .u16 => .u16,
        .u32 => .u32,
        else => return error.UnsupportedIndexType,
    };
    const index_data = try createIndexBuffer(
        allocator,
        indices,
        index_type,
    );
    errdefer allocator.free(index_data);

    return .{
        .allocator = allocator,
        .data = index_data,
        .index_type = index_type,
        .num_indices = num_indices,
    };
}

pub fn saveVertexFile(
    path: []const u8,
    data: *const VertexBufferData,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try utils.Serializer.writeHeader(
        file.writer(),
        gfx_types.VertexBufferMagic,
        gfx_types.VertexBufferVersion,
    );
    try utils.Serializer.write(file.writer(), data.layout);
    try utils.Serializer.write(file.writer(), data.data);
}

pub fn saveIndexFile(
    path: []const u8,
    data: *const IndexBufferData,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try utils.Serializer.writeHeader(
        file.writer(),
        gfx_types.IndexBufferMagic,
        gfx_types.IndexBufferVersion,
    );
    try utils.Serializer.write(file.writer(), data.index_type);
    try utils.Serializer.write(file.writer(), data.data);
}

pub fn saveMeshData(path: []const u8, data: *const assets.MeshData) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try utils.Serializer.writeHeader(
        file.writer(),
        assets.MeshMagic,
        assets.MeshVersion,
    );
    try utils.Serializer.write(file.writer(), data);
}
