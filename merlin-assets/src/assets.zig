const std = @import("std");

const utils = @import("merlin_utils");

// *********************************************************************************************
// Constants
// *********************************************************************************************

pub const AssetHandle = u16;
pub const MaxAssetHandles = 1024;
pub const MaxSubMeshes = 16;

pub const MeshMagic = @as(u32, @bitCast([_]u8{ 'M', 'M', 'S', 'H' }));
pub const MeshVersion: u8 = 1;

pub const MaterialMagic = @as(u32, @bitCast([_]u8{ 'M', 'M', 'A', 'T' }));
pub const MaterialVersion: u8 = 1;

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const SubMeshData = struct {
    vertices_count: u32,
    indices_count: u32,
};

pub const MeshData = struct {
    sub_mesh_count: u8,
    sub_meshes: [MaxSubMeshes]SubMeshData,
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
    alpha_mode: utils.gfx_types.AlphaMode,
    alpha_cutoff: f32,
    double_sided: bool,
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

var asset_handles: utils.HandlePool(AssetHandle, MaxAssetHandles) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    asset_handles = .init();
}

pub fn deinit() void {
    asset_handles.deinit();
}

pub fn loadMesh(filename: []const u8) !AssetHandle {
    _ = filename;

    return 0;
}
