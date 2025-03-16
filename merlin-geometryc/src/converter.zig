const std = @import("std");

const mcl = @import("merlin_core_layer");
const gfx = mcl.gfx;

const c = @import("c.zig").c;
const Gltf = @import("gltf.zig").Gltf;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn attributeTypeFromGfx(attribute: gfx.VertexAttributeType) c.cgltf_attribute_type {
    return switch (attribute) {
        .position => c.cgltf_attribute_type_position,
        .normal => c.cgltf_attribute_type_normal,
        .tangent => c.cgltf_attribute_type_tangent,
        .bitangent => c.cgltf_attribute_type_invalid,
        .color_0 => c.cgltf_attribute_type_color,
        .color_1 => c.cgltf_attribute_type_invalid,
        .color_2 => c.cgltf_attribute_type_invalid,
        .color_3 => c.cgltf_attribute_type_invalid,
        .indices => c.cgltf_attribute_type_invalid,
        .weight => c.cgltf_attribute_type_weights,
        .tex_coord_0 => c.cgltf_attribute_type_texcoord,
        .tex_coord_1 => c.cgltf_attribute_type_invalid,
        .tex_coord_2 => c.cgltf_attribute_type_invalid,
        .tex_coord_3 => c.cgltf_attribute_type_invalid,
        .tex_coord_4 => c.cgltf_attribute_type_invalid,
        .tex_coord_5 => c.cgltf_attribute_type_invalid,
        .tex_coord_6 => c.cgltf_attribute_type_invalid,
        .tex_coord_7 => c.cgltf_attribute_type_invalid,
    };
}

fn componentCountFromCgltf(type_: c.cgltf_type) !u8 {
    return switch (type_) {
        c.cgltf_type_scalar => 1,
        c.cgltf_type_vec2 => 2,
        c.cgltf_type_vec3 => 3,
        c.cgltf_type_vec4 => 4,
        else => error.UnsupportedType,
    };
}

fn componentTypeFromCgltf(component: c.cgltf_component_type) !gfx.VertexComponentType {
    return switch (component) {
        c.cgltf_component_type_r_8 => .i8,
        c.cgltf_component_type_r_8u => .u8,
        c.cgltf_component_type_r_16 => .i16,
        c.cgltf_component_type_r_16u => .u16,
        c.cgltf_component_type_r_32u => .u32,
        c.cgltf_component_type_r_32f => .f32,
        else => error.UnsupportedComponentType,
    };
}

fn indexTypeFromCgltf(component: c.cgltf_component_type) !gfx.IndexType {
    return switch (component) {
        c.cgltf_component_type_r_8u => .u8,
        c.cgltf_component_type_r_16u => .u16,
        c.cgltf_component_type_r_32u => .u32,
        else => error.UnsupportedComponentType,
    };
}

fn addVertexAttribute(
    vertex_layout: *gfx.VertexLayout,
    attribute_type: gfx.VertexAttributeType,
    gltf: Gltf,
    mesh_index: usize,
    primitive_index: usize,
) !void {
    const attribute_index = gltf.findMeshPrimitiveAttributeIndex(
        mesh_index,
        primitive_index,
        attributeTypeFromGfx(attribute_type),
    ) orelse return error.AttributeNotFound;

    const is_normalized = gltf.getMeshPrimitiveAttributeDataNormalized(
        mesh_index,
        primitive_index,
        attribute_index,
    );
    const type_ = gltf.getMeshPrimitiveAttributeDataType(
        mesh_index,
        primitive_index,
        attribute_index,
    );
    const component_type = gltf.getMeshPrimitiveAttributeDataComponentType(
        mesh_index,
        primitive_index,
        attribute_index,
    );

    vertex_layout.add(
        attribute_type,
        try componentCountFromCgltf(type_),
        try componentTypeFromCgltf(component_type),
        is_normalized,
    );
}

fn calculateVertexLayout(
    gltf: Gltf,
    mesh_index: usize,
    primitive_index: usize,
    normal: bool,
    tangent: bool,
    color: bool,
    weight: bool,
    tex_coord: bool,
) !gfx.VertexLayout {
    var vertex_layout = gfx.VertexLayout.init();

    try addVertexAttribute(
        &vertex_layout,
        .position,
        gltf,
        mesh_index,
        primitive_index,
    );

    if (normal) {
        try addVertexAttribute(
            &vertex_layout,
            .normal,
            gltf,
            mesh_index,
            primitive_index,
        );
    }

    if (tangent) {
        try addVertexAttribute(
            &vertex_layout,
            .tangent,
            gltf,
            mesh_index,
            primitive_index,
        );
    }

    if (color) {
        try addVertexAttribute(
            &vertex_layout,
            .color_0,
            gltf,
            mesh_index,
            primitive_index,
        );
    }

    if (weight) {
        try addVertexAttribute(
            &vertex_layout,
            .weight,
            gltf,
            mesh_index,
            primitive_index,
        );
    }

    if (tex_coord) {
        try addVertexAttribute(
            &vertex_layout,
            .tex_coord_0,
            gltf,
            mesh_index,
            primitive_index,
        );
    }

    return vertex_layout;
}

fn createVertexBuffer(
    allocator: std.mem.Allocator,
    gltf: Gltf,
    mesh_index: usize,
    primitive_index: usize,
    vertex_layout: gfx.VertexLayout,
) ![]const u8 {
    const num_vertices = gltf.getMeshPrimitiveVerticesCount(
        mesh_index,
        primitive_index,
    );

    const vertex_data_size = num_vertices * vertex_layout.stride;
    const vertex_data = try allocator.alloc(u8, vertex_data_size);
    errdefer allocator.free(vertex_data);

    for (0..vertex_layout.attributes.len) |attribute_index| {
        const attribute = &vertex_layout.attributes[attribute_index];
        const attribute_type: gfx.VertexAttributeType = @enumFromInt(attribute_index);
        if (attribute.num == 0) continue;

        const gltf_attribute_index = gltf.findMeshPrimitiveAttributeIndex(
            mesh_index,
            primitive_index,
            attributeTypeFromGfx(attribute_type),
        ) orelse return error.AttributeNotFound;

        const input_data = gltf.getMeshPrimitiveAttributeData(
            mesh_index,
            primitive_index,
            gltf_attribute_index,
        );
        const input_stride = gltf.getMeshPrimitiveAttributeDataStride(
            mesh_index,
            primitive_index,
            gltf_attribute_index,
        );

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
    gltf: Gltf,
    mesh_index: usize,
    primitive_index: usize,
) ![]const u8 {
    const num_indices = gltf.getIndicesCount(
        mesh_index,
        primitive_index,
    );

    const index_type = try indexTypeFromCgltf(
        gltf.getMeshPrimitiveIndicesComponentType(
            mesh_index,
            primitive_index,
        ),
    );

    const index_data_size = num_indices * index_type.getSize();
    const index_data = try allocator.alloc(u8, index_data_size);
    errdefer allocator.free(index_data);

    const input_data = gltf.getMeshPrimitiveIndicesData(
        mesh_index,
        primitive_index,
    );

    for (0..num_indices) |index| {
        const input_offset = index * index_type.getSize();
        const output_offset = index * index_type.getSize();

        @memcpy(
            index_data[output_offset .. output_offset + index_type.getSize()],
            input_data[input_offset .. input_offset + index_type.getSize()],
        );
    }

    return index_data;
}

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const MeshPrimitive = struct {
    allocator: std.mem.Allocator,
    vertex_layout: gfx.VertexLayout,
    vertex_data: []const u8,
    index_type: gfx.IndexType,
    index_data: []const u8,
    num_vertices: usize,
    num_indices: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        gltf: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        normal: bool,
        tangent: bool,
        color: bool,
        weight: bool,
        tex_coord: bool,
    ) !MeshPrimitive {
        const vertex_layout = try calculateVertexLayout(
            gltf,
            mesh_index,
            primitive_index,
            normal,
            tangent,
            color,
            weight,
            tex_coord,
        );

        const vertex_data = try createVertexBuffer(
            allocator,
            gltf,
            mesh_index,
            primitive_index,
            vertex_layout,
        );
        errdefer allocator.free(vertex_data);

        const index_type = try indexTypeFromCgltf(
            gltf.getMeshPrimitiveIndicesComponentType(
                mesh_index,
                primitive_index,
            ),
        );

        const index_data = try createIndexBuffer(
            allocator,
            gltf,
            mesh_index,
            primitive_index,
        );
        errdefer allocator.free(index_data);

        const num_vertices = gltf.getMeshPrimitiveVerticesCount(
            mesh_index,
            primitive_index,
        );

        const num_indices = gltf.getIndicesCount(
            mesh_index,
            primitive_index,
        );

        return MeshPrimitive{
            .allocator = allocator,
            .vertex_layout = vertex_layout,
            .vertex_data = vertex_data,
            .index_type = index_type,
            .index_data = index_data,
            .num_vertices = num_vertices,
            .num_indices = num_indices,
        };
    }

    pub fn deinit(self: *const MeshPrimitive) void {
        self.allocator.free(self.vertex_data);
        self.allocator.free(self.index_data);
    }
};

pub const Mesh = struct {
    allocator: std.mem.Allocator,
    primitives: []MeshPrimitive,

    pub fn init(
        allocator: std.mem.Allocator,
        gltf: Gltf,
        mesh_index: usize,
        normal: bool,
        tangent: bool,
        color: bool,
        weight: bool,
        tex_coord: bool,
    ) !Mesh {
        const primitives_count = gltf.getMeshPrimitiveCount(mesh_index);

        var primitives = try allocator.alloc(MeshPrimitive, primitives_count);
        errdefer allocator.free(primitives);

        for (0..primitives_count) |primitive_index| {
            const primitive = try MeshPrimitive.init(
                allocator,
                gltf,
                mesh_index,
                primitive_index,
                normal,
                tangent,
                color,
                weight,
                tex_coord,
            );

            primitives[primitive_index] = primitive;
        }

        return Mesh{
            .allocator = allocator,
            .primitives = primitives,
        };
    }

    pub fn deinit(self: *const Mesh) void {
        for (self.primitives) |primitive| {
            primitive.deinit();
        }

        self.allocator.free(self.primitives);
    }
};
