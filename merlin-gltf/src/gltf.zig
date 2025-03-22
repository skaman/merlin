const std = @import("std");

const image = @import("merlin_image");
const ktx = @import("merlin_ktx");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;

const c = @import("c.zig").c;

pub const Gltf = struct {
    allocator: std.mem.Allocator,
    filename: []const u8,
    data: ?*c.cgltf_data,

    pub fn load(allocator: std.mem.Allocator, filename: []const u8) !Gltf {
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

        return .{
            .allocator = allocator,
            .filename = try allocator.dupe(u8, filename),
            .data = data,
        };
    }

    pub fn deinit(self: Gltf) void {
        std.debug.assert(self.data != null);

        self.allocator.free(self.filename);
        c.cgltf_free(self.data);
    }

    pub inline fn meshCount(self: *const Gltf) usize {
        std.debug.assert(self.data != null);

        return self.data.?.meshes_count;
    }

    pub inline fn mesh(self: *const Gltf, index: usize) Mesh {
        std.debug.assert(self.data != null);
        std.debug.assert(self.data.?.meshes_count > index);

        return .{ .mesh = @ptrCast(&self.data.?.meshes[index]) };
    }

    pub inline fn materialCount(self: *const Gltf) usize {
        std.debug.assert(self.data != null);

        return self.data.?.materials_count;
    }

    pub inline fn material(self: *const Gltf, index: usize) Material {
        std.debug.assert(self.data != null);
        std.debug.assert(self.data.?.materials_count > index);

        return .{ .material = self.data.?.materials[index] };
    }
};

pub const Mesh = struct {
    mesh: *c.cgltf_mesh,

    pub fn name(self: Mesh) []const u8 {
        std.debug.assert(self.mesh != null);

        if (self.mesh.name == null) {
            return &"";
        }

        return self.mesh.name[0..std.mem.len(self.mesh.name)];
    }

    pub inline fn primitiveCount(self: Mesh) usize {
        return self.mesh.primitives_count;
    }

    pub inline fn primitive(self: Mesh, index: usize) Primitive {
        std.debug.assert(self.mesh.primitives_count > index);

        return .{ .primitive = &self.mesh.primitives[index] };
    }
};

pub const Primitive = struct {
    primitive: ?*c.cgltf_primitive,

    pub inline fn attributeCount(self: Primitive) usize {
        std.debug.assert(self.primitive != null);

        return self.primitive.?.attributes_count;
    }

    pub inline fn attribute(self: Primitive, index: usize) Attribute {
        std.debug.assert(self.primitive != null);
        std.debug.assert(self.primitive.?.attributes_count > index);

        return .{ .attribute = &self.primitive.?.attributes[index] };
    }

    pub fn attributeByType(self: Primitive, attributeType: gfx_types.VertexAttributeType) !?Attribute {
        for (0..self.attributeCount()) |index| {
            const attr = self.attribute(index);
            const attr_type = try attr.attributeType();
            if (attr_type == attributeType) {
                return attr;
            }
        }

        return null;
    }

    pub inline fn indices(self: Primitive) Accessor {
        std.debug.assert(self.primitive != null);

        return .{ .accessor = self.primitive.?.indices };
    }
};

pub const Attribute = struct {
    attribute: ?*c.cgltf_attribute,

    pub fn name(self: Attribute) []const u8 {
        std.debug.assert(self.attribute != null);

        if (self.attribute.?.name == null) {
            return &"";
        }

        return self.attribute.?.name[0..std.mem.len(self.attribute.name)];
    }

    pub fn attributeType(self: Attribute) !gfx_types.VertexAttributeType {
        std.debug.assert(self.attribute != null);

        return switch (self.attribute.?.type) {
            c.cgltf_attribute_type_position => .position,
            c.cgltf_attribute_type_normal => .normal,
            c.cgltf_attribute_type_tangent => .tangent,
            c.cgltf_attribute_type_texcoord => .tex_coord_0,
            c.cgltf_attribute_type_color => .color_0,
            c.cgltf_attribute_type_joints => error.UnsupportedAttributeType, // TODO: this should be supported
            c.cgltf_attribute_type_weights => .weight,
            else => error.UnsupportedAttributeType,
        };
    }

    pub fn accessor(self: Attribute) Accessor {
        std.debug.assert(self.attribute != null);

        return .{ .accessor = self.attribute.?.data };
    }
};

pub const Accessor = struct {
    accessor: *c.cgltf_accessor,

    pub fn name(self: Accessor) []const u8 {
        if (self.accessor.name == null) {
            return &"";
        }

        return self.accessor.name[0..std.mem.len(self.accessor.name)];
    }

    pub fn componentType(self: Accessor) !gfx_types.VertexComponentType {
        return switch (self.accessor.component_type) {
            c.cgltf_component_type_r_8 => .i8,
            c.cgltf_component_type_r_8u => .u8,
            c.cgltf_component_type_r_16 => .i16,
            c.cgltf_component_type_r_16u => .u16,
            c.cgltf_component_type_r_32u => .u32,
            c.cgltf_component_type_r_32f => .f32,
            else => error.UnsupportedComponentType,
        };
    }

    pub fn componentCount(self: Accessor) !usize {
        return switch (self.accessor.type) {
            c.cgltf_type_scalar => 1,
            c.cgltf_type_vec2 => 2,
            c.cgltf_type_vec3 => 3,
            c.cgltf_type_vec4 => 4,
            else => error.UnsupportedType,
        };
    }

    pub inline fn normalized(self: Accessor) bool {
        return self.accessor.normalized != 0;
    }

    pub inline fn stride(self: Accessor) usize {
        return self.accessor.stride;
    }

    pub inline fn count(self: Accessor) usize {
        return self.accessor.count;
    }

    pub inline fn data(self: Accessor) []const u8 {
        const buffer_view = self.accessor.buffer_view;
        const data_addr = @as([*c]const u8, @ptrCast(buffer_view.*.buffer.*.data)) +
            self.accessor.offset + buffer_view.*.offset;

        return data_addr[0..buffer_view.*.size];
    }
};

pub const Material = struct {
    material: *c.cgltf_material,

    pub fn name(self: Material) []const u8 {
        std.debug.assert(self.material != null);

        if (self.material.name == null) {
            return &"";
        }

        return self.material.name[0..std.mem.len(self.material.name)];
    }

    pub inline fn hasPbrMetallicRoughness(self: Material) bool {
        std.debug.assert(self.material != null);

        return self.material.has_pbr_metallic_roughness != 0;
    }

    pub inline fn hasPbrSpecularGlossiness(self: Material) bool {
        std.debug.assert(self.material != null);

        return self.material.has_pbr_specular_glossiness != 0;
    }

    pub inline fn pbrMetallicRoughness(self: Material) PbrMetallicRoughness {
        std.debug.assert(self.material != null);

        return .{
            .pbr_metallic_roughness = self.material.pbr_metallic_roughness,
        };
    }

    pub inline fn pbrSpecularGlossiness(self: Material) PbrSpecularGlossiness {
        std.debug.assert(self.material != null);

        return .{
            .pbr_specular_glossiness = self.material.pbr_specular_glossiness,
        };
    }
};

pub const PbrMetallicRoughness = struct {
    pbr_metallic_roughness: c.cgltf_pbr_metallic_roughness,

    pub fn baseColorTexture(self: PbrMetallicRoughness) !Texture {
        std.debug.assert(self.pbr_metallic_roughness.base_color_texture.texture != null);

        return Texture{ .texture = self.pbr_metallic_roughness.base_color_texture.texture };
    }

    pub fn baseColorFactor(self: PbrMetallicRoughness) [4]f32 {
        return self.pbr_metallic_roughness.base_color_factor;
    }

    pub fn metallicRoughnessTexture(self: PbrMetallicRoughness) !Texture {
        std.debug.assert(self.pbr_metallic_roughness.metallic_roughness_texture.texture != null);

        return Texture{ .texture = self.pbr_metallic_roughness.metallic_roughness_texture.texture };
    }

    pub inline fn metallicFactor(self: PbrMetallicRoughness) f32 {
        return self.pbr_metallic_roughness.metallic_factor;
    }

    pub inline fn roughnessFactor(self: PbrMetallicRoughness) f32 {
        return self.pbr_metallic_roughness.roughness_factor;
    }
};

pub const PbrSpecularGlossiness = struct {
    pbr_specular_glossiness: c.cgltf_pbr_specular_glossiness,

    pub fn diffuseTexture(self: PbrSpecularGlossiness) !Texture {
        std.debug.assert(self.pbr_specular_glossiness.diffuse_texture.texture != null);

        return Texture{ .texture = self.pbr_specular_glossiness.diffuse_texture.texture };
    }

    pub fn specularGlossinessTexture(self: PbrSpecularGlossiness) !Texture {
        std.debug.assert(self.pbr_specular_glossiness.specular_glossiness_texture.texture != null);

        return .{ .texture = self.pbr_specular_glossiness.specular_glossiness_texture.texture };
    }

    pub fn diffuseFactor(self: PbrSpecularGlossiness) [4]f32 {
        return self.pbr_specular_glossiness.diffuse_factor;
    }

    pub fn specularFactor(self: PbrSpecularGlossiness) [3]f32 {
        return self.pbr_specular_glossiness.specular_factor;
    }

    pub inline fn glossinessFactor(self: PbrSpecularGlossiness) f32 {
        return self.pbr_specular_glossiness.glossiness_factor;
    }
};

pub const Texture = struct {
    texture: *c.cgltf_texture,

    pub fn name(self: Texture) []const u8 {
        std.debug.assert(self.texture != null);

        if (self.texture.name == null) {
            return &"";
        }

        return self.texture.name[0..std.mem.len(self.texture.name)];
    }

    pub fn uri(self: Texture) ?[]const u8 {
        std.debug.assert(self.texture.image != null);

        const result = self.texture.image.uri;
        if (result == null) {
            return null;
        }

        return result[0..std.mem.len(result)];
    }
};

//pub const Gltf = struct {
//    allocator: std.mem.Allocator,
//    filename: []const u8,
//    data: ?*c.cgltf_data,
//
//    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Gltf {
//        const options: c.cgltf_options = std.mem.zeroes(c.cgltf_options);
//        var data: ?*c.cgltf_data = null;
//
//        const filename_z = try allocator.dupeZ(u8, filename);
//        defer allocator.free(filename_z);
//
//        if (c.cgltf_parse_file(
//            &options,
//            filename_z,
//            &data,
//        ) != c.cgltf_result_success) {
//            return error.ParseFailed;
//        }
//        errdefer c.cgltf_free(data);
//
//        if (c.cgltf_load_buffers(
//            &options,
//            data,
//            filename_z,
//        ) != c.cgltf_result_success) {
//            return error.LoadBuffersFailed;
//        }
//
//        return .{
//            .allocator = allocator,
//            .filename = try allocator.dupe(u8, filename),
//            .data = data,
//        };
//    }
//
//    pub fn deinit(self: Gltf) void {
//        std.debug.assert(self.data != null);
//
//        self.allocator.free(self.filename);
//        c.cgltf_free(self.data);
//    }
//
//    // *********************************************************************************************
//    // Mesh
//    // *********************************************************************************************
//
//    pub inline fn getMeshesCount(self: Gltf) usize {
//        std.debug.assert(self.data != null);
//
//        return self.data.?.meshes_count;
//    }
//
//    pub inline fn getMeshPrimitiveCount(self: Gltf, mesh_index: usize) usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//
//        return self.data.?.meshes[mesh_index].primitives_count;
//    }
//
//    // *********************************************************************************************
//    // Mesh vertices
//    // *********************************************************************************************
//
//    pub inline fn getMeshPrimitiveVerticesCount(self: Gltf, mesh_index: usize, primitive_index: usize) usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[0].data.*.count;
//    }
//
//    pub inline fn getMeshPrimitiveAttributesCount(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count;
//    }
//
//    pub inline fn getMeshPrimitiveAttributeType(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_index: usize,
//    ) c.cgltf_attribute_type {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].type;
//    }
//
//    pub fn findMeshPrimitiveAttributeIndex(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_type: c.cgltf_attribute_type,
//    ) ?usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const primitive = &self.data.?.meshes[mesh_index].primitives[primitive_index];
//        for (0..primitive.attributes_count) |index| {
//            if (primitive.attributes[index].type == attribute_type) {
//                return index;
//            }
//        }
//
//        return null;
//    }
//
//    pub inline fn getMeshPrimitiveAttributeDataComponentType(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_index: usize,
//    ) c.cgltf_component_type {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.component_type;
//    }
//
//    pub inline fn getMeshPrimitiveAttributeDataNormalized(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_index: usize,
//    ) bool {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.normalized != 0;
//    }
//
//    pub inline fn getMeshPrimitiveAttributeDataType(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_index: usize,
//    ) c.cgltf_type {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.type;
//    }
//
//    pub inline fn getMeshPrimitiveAttributeDataStride(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_index: usize,
//    ) usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data.*.stride;
//    }
//
//    pub inline fn getMeshPrimitiveAttributeData(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        attribute_index: usize,
//    ) []const u8 {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        std.debug.assert(attribute_index < self.data.?.meshes[mesh_index].primitives[primitive_index].attributes_count);
//
//        const accessor =
//            self.data.?.meshes[mesh_index].primitives[primitive_index].attributes[attribute_index].data;
//        const buffer_view = accessor.*.buffer_view;
//        const data_addr = @as([*c]const u8, @ptrCast(buffer_view.*.buffer.*.data)) +
//            accessor.*.offset + buffer_view.*.offset;
//
//        return data_addr[0..buffer_view.*.size];
//    }
//
//    // *********************************************************************************************
//    // Mesh indices
//    // *********************************************************************************************
//
//    pub inline fn getIndicesCount(self: Gltf, mesh_index: usize, primitive_index: usize) usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].indices.*.count;
//    }
//
//    pub inline fn getMeshPrimitiveIndicesComponentType(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) c.cgltf_component_type {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].indices.*.component_type;
//    }
//
//    pub inline fn getMeshPrimitiveIndicesStride(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) usize {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].indices.*.stride;
//    }
//
//    pub inline fn getMeshPrimitiveIndicesData(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) []const u8 {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const accessor = self.data.?.meshes[mesh_index].primitives[primitive_index].indices;
//        const buffer_view = accessor.*.buffer_view;
//        const data_addr = @as([*c]const u8, @ptrCast(buffer_view.*.buffer.*.data)) +
//            accessor.*.offset + buffer_view.*.offset;
//
//        return data_addr[0..buffer_view.*.size];
//    }
//
//    // *********************************************************************************************
//    // Mesh material
//    // *********************************************************************************************
//
//    pub inline fn getMeshPrimitiveHaveMaterial(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) bool {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        return self.data.?.meshes[mesh_index].primitives[primitive_index].material != null;
//    }
//
//    pub inline fn getMeshPrimitiveMaterialPbrBaseColorTexture(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//        srgb: bool,
//    ) !?ktx.Texture {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        if (material.*.pbr_metallic_roughness.base_color_texture.texture == null) {
//            return null;
//        }
//
//        const uri = material.*.pbr_metallic_roughness.base_color_texture.texture.*.image.*.uri;
//        const base_path = std.fs.path.dirname(self.filename) orelse ".";
//
//        const path = try std.fs.path.join(
//            self.allocator,
//            &[_][]const u8{ base_path, uri[0..std.mem.len(uri)] },
//        );
//        defer self.allocator.free(path);
//
//        return try ktx.Texture.init(self.allocator, path, srgb);
//    }
//
//    pub inline fn getMeshPrimitiveMaterialPbrMetallicRoughnessTexture(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) !?ktx.Texture {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        if (material.*.pbr_metallic_roughness.metallic_roughness_texture.texture == null) {
//            return null;
//        }
//
//        const uri = material.*.pbr_metallic_roughness.metallic_roughness_texture.texture.*.image.*.uri;
//        const base_path = std.fs.path.dirname(self.filename) orelse ".";
//
//        const path = try std.fs.path.join(
//            self.allocator,
//            &[_][]const u8{ base_path, uri[0..std.mem.len(uri)] },
//        );
//        defer self.allocator.free(path);
//
//        return try ktx.Texture.init(path);
//    }
//
//    pub inline fn getMeshPrimitiveMaterialPbrBaseColorFactor(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) []const f32 {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        return &material.*.pbr_metallic_roughness.base_color_factor;
//    }
//
//    pub inline fn getMeshPrimitiveMaterialPbrMetallicFactor(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) f32 {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        return material.*.pbr_metallic_roughness.metallic_factor;
//    }
//
//    pub inline fn getMeshPrimitiveMaterialPbrRoughnessFactor(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) f32 {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        return material.*.pbr_metallic_roughness.roughness_factor;
//    }
//
//    pub inline fn getMeshPrimitiveMaterialNormalTexture(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) !?ktx.Texture {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        if (material.*.normal_texture.texture == null) {
//            return null;
//        }
//
//        const uri = material.*.normal_texture.texture.*.image.*.uri;
//        const base_path = std.fs.path.dirname(self.filename) orelse ".";
//
//        const path = try std.fs.path.join(
//            self.allocator,
//            &[_][]const u8{ base_path, uri[0..std.mem.len(uri)] },
//        );
//        defer self.allocator.free(path);
//
//        return try ktx.Texture.init(path);
//    }
//
//    pub inline fn getMeshPrimitiveMaterialOcclusionTexture(
//        self: Gltf,
//        mesh_index: usize,
//        primitive_index: usize,
//    ) !?ktx.Texture {
//        std.debug.assert(self.data != null);
//        std.debug.assert(mesh_index < self.data.?.meshes_count);
//        std.debug.assert(primitive_index < self.data.?.meshes[mesh_index].primitives_count);
//
//        const material = self.data.?.meshes[mesh_index].primitives[primitive_index].material;
//        if (material.*.occlusion_texture.texture == null) {
//            return null;
//        }
//
//        const uri = material.*.occlusion_texture.texture.*.image.*.uri;
//        const base_path = std.fs.path.dirname(self.filename) orelse ".";
//
//        const path = try std.fs.path.join(
//            self.allocator,
//            &[_][]const u8{ base_path, uri[0..std.mem.len(uri)] },
//        );
//        defer self.allocator.free(path);
//
//        return try ktx.Texture.init(path);
//    }
//};
