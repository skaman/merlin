const std = @import("std");

const gfx_types = @import("gfx_types.zig");

// *********************************************************************************************
// Constants
// *********************************************************************************************

pub const MeshMagic = @as(u32, @bitCast([_]u8{ 'M', 'M', 'S', 'H' }));
pub const MeshVersion: u8 = 1;

pub const MaterialMagic = @as(u32, @bitCast([_]u8{ 'M', 'M', 'A', 'T' }));
pub const MaterialVersion: u8 = 1;

pub const MaxSubMeshes = 16;

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

pub const MeshData = struct {
    vertex_layout: gfx_types.VertexLayout,
    vertices_count: u32,
    vertices_data_size: u32,
    index_type: gfx_types.IndexType,
    indices_count: u32,
    indices_data_size: u32,
};

pub const MaterialPbrMetallicRoughness = struct {
    base_color_texture_index: ?u8,
    base_color_factor: [4]f32,
    metallic_roughness_texture_index: ?u8,
    metallic_factor: f32,
    roughness_factor: f32,
};

pub const MaterialPbrSpecularGlossiness = struct {
    diffuse_texture_index: ?u8,
    diffuse_factor: [4]f32,
    specular_glossiness_texture_index: ?u8,
    specular_factor: [3]f32,
    glossiness_factor: f32,
};

pub const MaterialData = struct {
    pbr_metallic_roughness: ?MaterialPbrMetallicRoughness,
    pbr_specular_glossiness: ?MaterialPbrSpecularGlossiness,
    normal_texture_index: ?u8,
    occlusion_texture_index: ?u8,
    emissive_texture_index: ?u8,
    emissive_factor: [3]f32,
    alpha_mode: gfx_types.AlphaMode,
    alpha_cutoff: f32,
    double_sided: bool,
};
