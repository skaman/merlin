const std = @import("std");

const mcl = @import("merlin_core_layer");
const gfx = mcl.gfx;

const c = @import("c.zig").c;

pub const Gltf = struct {
    data: ?*c.cgltf_data,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Gltf {
        const options: c.cgltf_options = std.mem.zeroes(c.cgltf_options);
        var data: ?*c.cgltf_data = null;

        const filename_z = try allocator.dupeZ(u8, filename);
        defer allocator.free(filename_z);

        if (c.cgltf_parse_file(
            &options,
            filename_z,
            &data,
        ) != c.cgltf_result_success) {
            return error.ParseFailed;
        }
        errdefer c.cgltf_free(data);

        if (c.cgltf_load_buffers(
            &options,
            data,
            filename_z,
        ) != c.cgltf_result_success) {
            return error.LoadBuffersFailed;
        }

        return .{ .data = data };
    }

    pub fn deinit(self: Gltf) void {
        std.debug.assert(self.data != null);
        c.cgltf_free(self.data);
    }

    // *********************************************************************************************
    // Mesh
    // *********************************************************************************************

    pub inline fn getMeshesCount(self: Gltf) usize {
        std.debug.assert(self.data != null);

        return self.data.?.meshes_count;
    }

    pub inline fn getMeshPrimitiveCount(self: Gltf, mesh_index: usize) usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);

        return self.data.?.meshes[mesh_index].primitives_count;
    }

    // *********************************************************************************************
    // Mesh vertices
    // *********************************************************************************************

    pub inline fn getMeshPrimitiveVerticesCount(self: Gltf, mesh_index: usize, primitive_index: usize) usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[0].data.*.count;
    }

    pub inline fn getMeshPrimitiveAttributesCount(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
    ) usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count;
    }

    pub inline fn getMeshPrimitiveAttributeType(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_index: usize,
    ) c.cgltf_attribute_type {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].type;
    }

    pub fn findMeshPrimitiveAttributeIndex(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_type: c.cgltf_attribute_type,
    ) ?usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);

        const primitive = &self.data.?.meshes[mesh_index].primitives[primitive_index];
        for (0..primitive.attributes_count) |index| {
            if (primitive.attributes[index].type == attribute_type) {
                return index;
            }
        }

        return null;
    }

    pub inline fn getMeshPrimitiveAttributeDataComponentType(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_index: usize,
    ) c.cgltf_component_type {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.component_type;
    }

    pub inline fn getMeshPrimitiveAttributeDataNormalized(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_index: usize,
    ) bool {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.normalized != 0;
    }

    pub inline fn getMeshPrimitiveAttributeDataType(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_index: usize,
    ) c.cgltf_type {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.type;
    }

    pub inline fn getMeshPrimitiveAttributeDataStride(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_index: usize,
    ) usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.stride;
    }

    pub inline fn getMeshPrimitiveAttributeData(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
        attribute_index: usize,
    ) []const u8 {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);

        const accessor =
            self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data;
        const buffer_view = accessor.*.buffer_view;
        const data_addr = @as([*c]const u8, @ptrCast(buffer_view.*.buffer.*.data)) +
            accessor.*.offset + buffer_view.*.offset;

        return data_addr[0..buffer_view.*.size];
    }

    // *********************************************************************************************
    // Mesh indices
    // *********************************************************************************************

    pub inline fn getIndicesCount(self: Gltf, mesh_index: usize, primitive_index: usize) usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
        return self.data.?.meshes[mesh_index].primitives[primitive_index].indices.*.count;
    }

    pub inline fn getMeshPrimitiveIndicesComponentType(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
    ) c.cgltf_component_type {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].indices.*.component_type;
    }

    pub inline fn getMeshPrimitiveIndicesStride(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
    ) usize {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);

        return self.data.?.meshes[mesh_index].primitives[primitive_index].indices.*.stride;
    }

    pub inline fn getMeshPrimitiveIndicesData(
        self: Gltf,
        mesh_index: usize,
        primitive_index: usize,
    ) []const u8 {
        std.debug.assert(self.data != null);
        std.debug.assert(mesh_index < self.data.?.meshes_count);
        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);

        const accessor = self.data.?.meshes[mesh_index].primitives[primitive_index].indices;
        const buffer_view = accessor.*.buffer_view;
        const data_addr = @as([*c]const u8, @ptrCast(buffer_view.*.buffer.*.data)) +
            accessor.*.offset + buffer_view.*.offset;

        return data_addr[0..buffer_view.*.size];
    }
};
