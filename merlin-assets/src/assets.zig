const std = @import("std");

const gfx = @import("merlin_gfx");
const utils = @import("merlin_utils");
const asset_types = utils.asset_types;
const gfx_types = utils.gfx_types;

// *********************************************************************************************
// Structs
// *********************************************************************************************

const log = std.log.scoped(.assets);

pub const Mesh = struct {
    pipeline_handle: gfx.PipelineLayoutHandle,
    buffer_handle: gfx.BufferHandle,
    vertex_buffer_offset: u32,
    index_buffer_offset: u32,
    index_type: gfx_types.IndexType,
    indices_count: u32,
};

pub const Material = struct {
    // PBR Metallic Roughness
    base_color_texture_handle: ?gfx.TextureHandle,
    base_color_factor: [4]f32,
    metallic_roughness_texture_handle: ?gfx.TextureHandle,
    metallic_factor: f32,
    roughness_factor: f32,

    // PBR Specular Glossiness
    diffuse_texture_handle: ?gfx.TextureHandle,
    diffuse_factor: [4]f32,
    specular_glossiness_texture_handle: ?gfx.TextureHandle,
    specular_factor: [3]f32,
    glossiness_factor: f32,

    // Common
    normal_texture_handle: ?gfx.TextureHandle,
    occlusion_texture_handle: ?gfx.TextureHandle,
    emissive_texture_handle: ?gfx.TextureHandle,
    emissive_factor: [3]f32,
    alpha_mode: gfx_types.AlphaMode,
    alpha_cutoff: f32,
    double_sided: bool,
};

pub const MeshHandle = enum(u16) { _ };
pub const MaterialHandle = enum(u16) { _ };

pub const MaxMeshHandles = 512;
pub const MaxMaterialHandles = 512;

// *********************************************************************************************
// Globals
// *********************************************************************************************

var gpa: std.mem.Allocator = undefined;
var arena_impl: std.heap.ArenaAllocator = undefined;
var arena: std.mem.Allocator = undefined;

var assets_path: []const u8 = undefined;

var meshes: utils.HandleArray(
    MeshHandle,
    Mesh,
    MaxMeshHandles,
) = undefined;

var mesh_handles: utils.HandlePool(
    MeshHandle,
    MaxMeshHandles,
) = undefined;

var materials: utils.HandleArray(
    MaterialHandle,
    Material,
    MaxMaterialHandles,
) = undefined;

var material_handles: utils.HandlePool(
    MaterialHandle,
    MaxMaterialHandles,
) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn getAssetsPath(allocator: std.mem.Allocator) ![]const u8 {
    return try std.fs.path.join(allocator, &[_][]const u8{
        try std.fs.selfExeDirPathAlloc(arena),
        std.mem.bytesAsSlice(u8, "assets"),
    });
}

fn getAssetPath(allocator: std.mem.Allocator, asset_name: []const u8) ![]const u8 {
    return try std.fs.path.join(allocator, &[_][]const u8{
        assets_path,
        asset_name,
    });
}

fn loadMaterialTexture(
    dirname: []const u8,
    basename: []const u8,
    texture_index: ?u8,
) !?gfx.TextureHandle {
    if (texture_index) |index| {
        const base_color_texture_filename = try std.fmt.allocPrint(
            arena,
            "{s}.{d}.ktx",
            .{
                basename,
                index,
            },
        );
        const base_color_texture_path = try getAssetPath(
            arena,
            try std.fs.path.join(
                arena,
                &[_][]const u8{
                    dirname,
                    base_color_texture_filename,
                },
            ),
        );

        log.debug("Base color texture path: {s}", .{base_color_texture_path});

        var texture_file = try std.fs.cwd().openFile(base_color_texture_path, .{});
        defer texture_file.close();

        const stats = try texture_file.stat();
        const texture_reader = texture_file.reader().any();

        return try gfx.createTexture(
            texture_reader,
            @intCast(stats.size),
        );
    }

    return null;
}

fn destroyMaterialTexture(
    texture_handle: ?gfx.TextureHandle,
) void {
    if (texture_handle) |handle| {
        gfx.destroyTexture(handle);
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(allocator: std.mem.Allocator) !void {
    log.debug("Initializing assets", .{});

    gpa = allocator;

    arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena_impl.deinit();
    arena = arena_impl.allocator();

    mesh_handles = .init();
    errdefer mesh_handles.deinit();

    material_handles = .init();
    errdefer material_handles.deinit();

    assets_path = try getAssetsPath(gpa);
    errdefer allocator.free(assets_path);

    _ = arena_impl.reset(.retain_capacity);
}

pub fn deinit() void {
    log.debug("Deinitializing assets", .{});

    gpa.free(assets_path);
    material_handles.deinit();
    mesh_handles.deinit();
    arena_impl.deinit();
}

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

pub fn loadMesh(filename: []const u8) !MeshHandle {
    defer _ = arena_impl.reset(.retain_capacity);

    const path = try getAssetPath(arena, filename);
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader().any();

    const handle = mesh_handles.create();
    errdefer mesh_handles.destroy(handle);

    const mesh_data = try readMesh(arena, reader);
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

    meshes.setValue(handle, .{
        .pipeline_handle = pipeline_handle,
        .buffer_handle = buffer_handle,
        .vertex_buffer_offset = 0,
        .index_buffer_offset = mesh_data.vertices_data_size,
        .index_type = mesh_data.index_type,
        .indices_count = mesh_data.indices_count,
    });

    log.debug("Loaded mesh: {s}", .{filename});
    log.debug("  - Vertices count: {d}", .{mesh_data.vertices_count});
    log.debug("  - Vertices data size: {s}", .{std.fmt.fmtIntSizeDec(mesh_data.vertices_data_size)});
    log.debug("  - Indices count: {d}", .{mesh_data.indices_count});
    log.debug("  - Indices data size: {s}", .{std.fmt.fmtIntSizeDec(mesh_data.indices_data_size)});
    log.debug("  - Index type: {s}", .{mesh_data.index_type.name()});
    log.debug("  - Pipeline layout handle: {d}", .{pipeline_handle});
    log.debug("  - Buffer handle: {d}", .{buffer_handle});

    return handle;
}

pub fn destroyMesh(handle: MeshHandle) void {
    const mesh_value = meshes.valuePtr(handle);
    gfx.destroyPipelineLayout(mesh_value.pipeline_handle);
    gfx.destroyBuffer(mesh_value.buffer_handle);
    mesh_handles.destroy(handle);
}

pub inline fn mesh(handle: MeshHandle) *Mesh {
    return meshes.valuePtr(handle);
}

pub fn readMaterial(allocator: std.mem.Allocator, reader: std.io.AnyReader) !asset_types.MaterialData {
    try utils.Serializer.checkHeader(
        reader,
        asset_types.MaterialMagic,
        asset_types.MaterialVersion,
    );
    return try utils.Serializer.read(
        asset_types.MaterialData,
        allocator,
        reader,
    );
}

pub fn loadMaterial(filename: []const u8) !MaterialHandle {
    defer _ = arena_impl.reset(.retain_capacity);

    const path = try getAssetPath(arena, filename);
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const reader = file.reader().any();

    const handle = material_handles.create();
    errdefer material_handles.destroy(handle);

    const material_data = try readMaterial(arena, reader);

    const base_color_texture_index = if (material_data.pbr_metallic_roughness) |value| value.base_color_texture_index else null;
    const base_color_factor = if (material_data.pbr_metallic_roughness) |value| value.base_color_factor else [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    const metallic_roughness_texture_index = if (material_data.pbr_metallic_roughness) |value| value.metallic_roughness_texture_index else null;
    const metallic_factor = if (material_data.pbr_metallic_roughness) |value| value.metallic_factor else 0.0;
    const roughness_factor = if (material_data.pbr_metallic_roughness) |value| value.roughness_factor else 1.0;

    const diffuse_texture_index = if (material_data.pbr_specular_glossiness) |value| value.diffuse_texture_index else null;
    const diffuse_factor = if (material_data.pbr_specular_glossiness) |value| value.diffuse_factor else [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    const specular_glossiness_texture_index = if (material_data.pbr_specular_glossiness) |value| value.specular_glossiness_texture_index else null;
    const specular_factor = if (material_data.pbr_specular_glossiness) |value| value.specular_factor else [3]f32{ 1.0, 1.0, 1.0 };
    const glossiness_factor = if (material_data.pbr_specular_glossiness) |value| value.glossiness_factor else 1.0;

    const dir = std.fs.path.dirname(filename) orelse ".";
    const basename = std.fs.path.stem(filename);

    const base_color_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        base_color_texture_index,
    );
    errdefer destroyMaterialTexture(base_color_texture_handle);

    const metallic_roughness_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        metallic_roughness_texture_index,
    );
    errdefer destroyMaterialTexture(metallic_roughness_texture_handle);

    const diffuse_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        diffuse_texture_index,
    );
    errdefer destroyMaterialTexture(diffuse_texture_handle);

    const specular_glossiness_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        specular_glossiness_texture_index,
    );
    errdefer destroyMaterialTexture(specular_glossiness_texture_handle);

    const normal_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        material_data.normal_texture_index,
    );
    errdefer destroyMaterialTexture(normal_texture_handle);

    const occlusion_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        material_data.occlusion_texture_index,
    );
    errdefer destroyMaterialTexture(occlusion_texture_handle);

    const emissive_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        material_data.emissive_texture_index,
    );
    errdefer destroyMaterialTexture(emissive_texture_handle);

    materials.setValue(handle, .{
        .base_color_texture_handle = base_color_texture_handle,
        .base_color_factor = base_color_factor,
        .metallic_roughness_texture_handle = metallic_roughness_texture_handle,
        .metallic_factor = metallic_factor,
        .roughness_factor = roughness_factor,

        .diffuse_texture_handle = diffuse_texture_handle,
        .diffuse_factor = diffuse_factor,
        .specular_glossiness_texture_handle = specular_glossiness_texture_handle,
        .specular_factor = specular_factor,
        .glossiness_factor = glossiness_factor,

        .normal_texture_handle = normal_texture_handle,
        .occlusion_texture_handle = occlusion_texture_handle,
        .emissive_texture_handle = emissive_texture_handle,
        .emissive_factor = material_data.emissive_factor,
        .alpha_mode = material_data.alpha_mode,
        .alpha_cutoff = material_data.alpha_cutoff,
        .double_sided = material_data.double_sided,
    });

    log.debug("Loaded material: {s}", .{filename});
    log.debug("  - Base color texture handle: {any}", .{base_color_texture_handle});
    log.debug("  - Base color factor: [{d}, {d}, {d}, {d}]", .{
        base_color_factor[0],
        base_color_factor[1],
        base_color_factor[2],
        base_color_factor[3],
    });
    log.debug("  - Metallic/Roughness texture handle: {any}", .{metallic_roughness_texture_handle});
    log.debug("  - Metallic factor: {d}", .{metallic_factor});
    log.debug("  - Roughness factor: {d}", .{roughness_factor});
    log.debug("  - Diffuse texture handle: {any}", .{diffuse_texture_handle});
    log.debug("  - Diffuse factor: [{d}, {d}, {d}, {d}]", .{
        diffuse_factor[0],
        diffuse_factor[1],
        diffuse_factor[2],
        diffuse_factor[3],
    });
    log.debug("  - Specular/Glossiness texture handle: {any}", .{specular_glossiness_texture_handle});
    log.debug("  - Specular factor: [{d}, {d}, {d}]", .{
        specular_factor[0],
        specular_factor[1],
        specular_factor[2],
    });
    log.debug("  - Glossiness factor: {d}", .{glossiness_factor});
    log.debug("  - Normal texture handle: {any}", .{normal_texture_handle});
    log.debug("  - Occlusion texture handle: {any}", .{occlusion_texture_handle});
    log.debug("  - Emissive texture handle: {any}", .{emissive_texture_handle});
    log.debug("  - Emissive factor: [{d}, {d}, {d}]", .{
        material_data.emissive_factor[0],
        material_data.emissive_factor[1],
        material_data.emissive_factor[2],
    });
    log.debug("  - Alpha mode: {s}", .{material_data.alpha_mode.name()});
    log.debug("  - Alpha cutoff: {d}", .{material_data.alpha_cutoff});
    log.debug("  - Double sided: {s}", .{if (material_data.double_sided) "true" else "false"});

    return handle;
}

pub fn destroyMaterial(handle: MaterialHandle) void {
    const material_value = materials.valuePtr(handle);
    destroyMaterialTexture(material_value.base_color_texture_handle);
    destroyMaterialTexture(material_value.metallic_roughness_texture_handle);
    destroyMaterialTexture(material_value.diffuse_texture_handle);
    destroyMaterialTexture(material_value.specular_glossiness_texture_handle);
    destroyMaterialTexture(material_value.normal_texture_handle);
    destroyMaterialTexture(material_value.occlusion_texture_handle);
    destroyMaterialTexture(material_value.emissive_texture_handle);
    material_handles.destroy(handle);
}

pub inline fn material(handle: MaterialHandle) *Material {
    return materials.valuePtr(handle);
}
