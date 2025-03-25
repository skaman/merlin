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

        return .{ .material = &self.data.?.materials[index] };
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
    material: ?*c.cgltf_material,

    pub fn name(self: Material) []const u8 {
        std.debug.assert(self.material != null);

        if (self.material.?.name == null) {
            return &"";
        }

        return self.material.?.name[0..std.mem.len(self.material.name)];
    }

    pub inline fn hasPbrMetallicRoughness(self: Material) bool {
        std.debug.assert(self.material != null);

        return self.material.?.has_pbr_metallic_roughness != 0;
    }

    pub inline fn hasPbrSpecularGlossiness(self: Material) bool {
        std.debug.assert(self.material != null);

        return self.material.?.has_pbr_specular_glossiness != 0;
    }

    pub inline fn pbrMetallicRoughness(self: Material) PbrMetallicRoughness {
        std.debug.assert(self.material != null);

        return .{
            .pbr_metallic_roughness = &self.material.?.pbr_metallic_roughness,
        };
    }

    pub inline fn pbrSpecularGlossiness(self: Material) PbrSpecularGlossiness {
        std.debug.assert(self.material != null);

        return .{
            .pbr_specular_glossiness = &self.material.?.pbr_specular_glossiness,
        };
    }

    pub inline fn normalTexture(self: Material) !?Texture {
        if (self.material.?.normal_texture.texture == null) {
            return null;
        }

        return .{ .texture = self.material.?.normal_texture.texture };
    }

    pub inline fn occlusionTexture(self: Material) !?Texture {
        if (self.material.?.occlusion_texture.texture == null) {
            return null;
        }
        return .{ .texture = self.material.?.occlusion_texture.texture };
    }

    pub inline fn emissiveTexture(self: Material) !?Texture {
        if (self.material.?.emissive_texture.texture == null) {
            return null;
        }
        return .{ .texture = self.material.?.emissive_texture.texture };
    }

    pub inline fn emissiveFactor(self: Material) [3]f32 {
        return self.material.?.emissive_factor;
    }

    pub inline fn alphaMode(self: Material) !gfx_types.AlphaMode {
        return switch (self.material.?.alpha_mode) {
            c.cgltf_alpha_mode_opaque => .opaque_,
            c.cgltf_alpha_mode_mask => .mask,
            c.cgltf_alpha_mode_blend => .blend,
            else => return error.UnsupportedAlphaMode,
        };
    }

    pub inline fn alphaCutoff(self: Material) f32 {
        return self.material.?.alpha_cutoff;
    }

    pub inline fn doubleSided(self: Material) bool {
        return self.material.?.double_sided != 0;
    }
};

pub const PbrMetallicRoughness = struct {
    pbr_metallic_roughness: *c.cgltf_pbr_metallic_roughness,

    pub fn baseColorTexture(self: PbrMetallicRoughness) !?Texture {
        if (self.pbr_metallic_roughness.base_color_texture.texture == null) {
            return null;
        }
        return .{ .texture = self.pbr_metallic_roughness.base_color_texture.texture };
    }

    pub fn baseColorFactor(self: PbrMetallicRoughness) [4]f32 {
        return self.pbr_metallic_roughness.base_color_factor;
    }

    pub fn metallicRoughnessTexture(self: PbrMetallicRoughness) !?Texture {
        if (self.pbr_metallic_roughness.metallic_roughness_texture.texture == null) {
            return null;
        }
        return .{ .texture = self.pbr_metallic_roughness.metallic_roughness_texture.texture };
    }

    pub inline fn metallicFactor(self: PbrMetallicRoughness) f32 {
        return self.pbr_metallic_roughness.metallic_factor;
    }

    pub inline fn roughnessFactor(self: PbrMetallicRoughness) f32 {
        return self.pbr_metallic_roughness.roughness_factor;
    }
};

pub const PbrSpecularGlossiness = struct {
    pbr_specular_glossiness: *c.cgltf_pbr_specular_glossiness,

    pub fn diffuseTexture(self: PbrSpecularGlossiness) !?Texture {
        if (self.pbr_specular_glossiness.diffuse_texture.texture == null) {
            return null;
        }
        return .{ .texture = self.pbr_specular_glossiness.diffuse_texture.texture };
    }

    pub fn specularGlossinessTexture(self: PbrSpecularGlossiness) !?Texture {
        if (self.pbr_specular_glossiness.specular_glossiness_texture.texture == null) {
            return null;
        }
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

        const result = self.texture.image.*.uri;
        if (result == null) {
            return null;
        }

        return result[0..std.mem.len(result)];
    }
};
