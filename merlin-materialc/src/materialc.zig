const std = @import("std");

const gltf = @import("merlin_gltf");
const image = @import("merlin_image");
const ktx = @import("merlin_ktx");
const texturec = @import("merlin_texturec");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;
const asset_types = utils.asset_types;

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const ConvertedMaterial = struct {
    material_data: asset_types.MaterialData,
    textures: std.ArrayList(ktx.Texture),

    pub fn deinit(self: ConvertedMaterial) void {
        for (self.textures.items) |texture| {
            texture.deinit();
        }
        self.textures.deinit();
    }
};

pub const Options = struct {
    compression: bool = false,
    level: u32 = 2,
    quality: u32 = 128,
    threads: ?u32 = null,
    mipmaps: bool = false,
    edge: image.ResizeEdge = .clamp,
    filter: image.ResizeFilter = .auto,
    srgb: bool = false,
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn convertGltfToKtxTexture(
    allocator: std.mem.Allocator,
    gltf_texture: gltf.Texture,
    base_path: []const u8,
    normalmap: bool,
    conversion_options: Options,
) !ktx.Texture {
    const gltf_texture_uri = gltf_texture.uri() orelse {
        std.log.err("Missing texture URI.\n", .{});
        return error.MissingTextureUri;
    };
    const path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ base_path, gltf_texture_uri },
    );
    defer allocator.free(path);

    return try texturec.convert(
        allocator,
        path,
        .{
            .compression = conversion_options.compression,
            .level = conversion_options.level,
            .quality = conversion_options.quality,
            .threads = conversion_options.threads,
            .mipmaps = conversion_options.mipmaps,
            .edge = conversion_options.edge,
            .filter = conversion_options.filter,
            .normalmap = normalmap,
        },
    );
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn convert(
    allocator: std.mem.Allocator,
    source: *const gltf.Gltf,
    base_path: []const u8,
    material_index: usize,
    conversion_options: Options,
) !ConvertedMaterial {
    const material = source.material(material_index);
    var converted_material = ConvertedMaterial{
        .material_data = .{
            .pbr_metallic_roughness = null,
            .pbr_specular_glossiness = null,
            .normal_texture_index = null,
            .occlusion_texture_index = null,
            .emissive_texture_index = null,
            .emissive_factor = [3]f32{ 0.0, 0.0, 0.0 },
            .alpha_mode = .opaque_,
            .alpha_cutoff = 0.5,
            .double_sided = false,
        },
        .textures = std.ArrayList(ktx.Texture).init(allocator),
    };
    errdefer converted_material.deinit();

    if (material.hasPbrMetallicRoughness()) {
        const pbr_metallic_roughness = material.pbrMetallicRoughness();

        const base_color_texture = try pbr_metallic_roughness.baseColorTexture();
        var base_color_texture_index: ?u8 = null;
        if (base_color_texture) |texture| {
            base_color_texture_index = @intCast(converted_material.textures.items.len);
            try converted_material.textures.append(try convertGltfToKtxTexture(
                allocator,
                texture,
                base_path,
                false,
                conversion_options,
            ));
        }

        const metallic_roughness_texture = try pbr_metallic_roughness.metallicRoughnessTexture();
        var metallic_roughness_texture_index: ?u8 = null;
        if (metallic_roughness_texture) |texture| {
            metallic_roughness_texture_index = @intCast(converted_material.textures.items.len);
            try converted_material.textures.append(try convertGltfToKtxTexture(
                allocator,
                texture,
                base_path,
                false,
                conversion_options,
            ));
        }

        converted_material.material_data.pbr_metallic_roughness = .{
            .base_color_texture_index = base_color_texture_index,
            .base_color_factor = pbr_metallic_roughness.baseColorFactor(),
            .metallic_roughness_texture_index = metallic_roughness_texture_index,
            .metallic_factor = pbr_metallic_roughness.metallicFactor(),
            .roughness_factor = pbr_metallic_roughness.roughnessFactor(),
        };
    }

    if (material.hasPbrSpecularGlossiness()) {
        const pbr_specular_glossiness = material.pbrSpecularGlossiness();

        const diffuse_texture = try pbr_specular_glossiness.diffuseTexture();
        var diffuse_texture_index: ?u8 = null;
        if (diffuse_texture) |texture| {
            diffuse_texture_index = @intCast(converted_material.textures.items.len);
            try converted_material.textures.append(try convertGltfToKtxTexture(
                allocator,
                texture,
                base_path,
                false,
                conversion_options,
            ));
        }

        const specular_glossiness_texture = try pbr_specular_glossiness.specularGlossinessTexture();
        var specular_glossiness_texture_index: ?u8 = null;
        if (specular_glossiness_texture) |texture| {
            specular_glossiness_texture_index = @intCast(converted_material.textures.items.len);
            try converted_material.textures.append(try convertGltfToKtxTexture(
                allocator,
                texture,
                base_path,
                false,
                conversion_options,
            ));
        }

        converted_material.material_data.pbr_specular_glossiness = .{
            .diffuse_texture_index = diffuse_texture_index,
            .diffuse_factor = pbr_specular_glossiness.diffuseFactor(),
            .specular_glossiness_texture_index = specular_glossiness_texture_index,
            .specular_factor = pbr_specular_glossiness.specularFactor(),
            .glossiness_factor = pbr_specular_glossiness.glossinessFactor(),
        };
    }

    const normal_texture = try material.normalTexture();
    if (normal_texture) |texture| {
        converted_material.material_data.normal_texture_index = @intCast(converted_material.textures.items.len);
        try converted_material.textures.append(try convertGltfToKtxTexture(
            allocator,
            texture,
            base_path,
            true,
            conversion_options,
        ));
    }

    const occlusion_texture = try material.occlusionTexture();
    if (occlusion_texture) |texture| {
        converted_material.material_data.occlusion_texture_index = @intCast(converted_material.textures.items.len);
        try converted_material.textures.append(try convertGltfToKtxTexture(
            allocator,
            texture,
            base_path,
            false,
            conversion_options,
        ));
    }

    const emissive_texture = try material.emissiveTexture();
    if (emissive_texture) |texture| {
        converted_material.material_data.emissive_texture_index = @intCast(converted_material.textures.items.len);
        try converted_material.textures.append(try convertGltfToKtxTexture(
            allocator,
            texture,
            base_path,
            false,
            conversion_options,
        ));
    }

    converted_material.material_data.emissive_factor = material.emissiveFactor();
    converted_material.material_data.alpha_mode = try material.alphaMode();
    converted_material.material_data.alpha_cutoff = material.alphaCutoff();
    converted_material.material_data.double_sided = material.doubleSided();

    return converted_material;
}

pub fn saveMaterialData(
    path: []const u8,
    material_data: *const asset_types.MaterialData,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try utils.Serializer.writeHeader(
        file.writer(),
        asset_types.MaterialMagic,
        asset_types.MaterialVersion,
    );
    try utils.Serializer.write(file.writer(), material_data);
}
