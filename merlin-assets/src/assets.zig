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
    pipeline_handle: gfx.PipelineLayoutHandle, // TODO: rename to PipelineLayoutHandle
    buffer_handle: gfx.BufferHandle,
    vertex_buffer_offset: u32,
    index_buffer_offset: u32,
    index_type: gfx_types.IndexType,
    indices_count: u32,
};

pub const MaterialPbrMetallicRoughness = struct {
    base_color_texture_handle: gfx.TextureHandle,
    base_color_factor: [4]f32,
    metallic_roughness_texture_handle: gfx.TextureHandle,
    metallic_factor: f32,
    roughness_factor: f32,
};

pub const MaterialPbrSpecularGlossiness = struct {
    diffuse_texture_handle: gfx.TextureHandle,
    diffuse_factor: [4]f32,
    specular_glossiness_texture_handle: gfx.TextureHandle,
    specular_factor: [3]f32,
    glossiness_factor: f32,
};

pub const MaterialType = enum {
    pbr_metallic_roughness,
    pbr_specular_glossiness,
};

pub const MaterialPbr = union(MaterialType) {
    pbr_metallic_roughness: MaterialPbrMetallicRoughness,
    pbr_specular_glossiness: MaterialPbrSpecularGlossiness,
};

pub const Material = struct {
    pbr: MaterialPbr,
    normal_texture_handle: gfx.TextureHandle,
    occlusion_texture_handle: gfx.TextureHandle,
    emissive_texture_handle: gfx.TextureHandle,
    emissive_factor: [3]f32,
    alpha_mode: gfx_types.AlphaMode,
    alpha_cutoff: f32,
    double_sided: bool,
};

const MaterialUniform = struct {
    base_color_factor: [4]f32,
    metallic_factor: f32,
    roughness_factor: f32,
    diffuse_factor: [4]f32,
    specular_factor: [3]f32,
    glossiness_factor: f32,
    emissive_factor: [3]f32,
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

var material_uniform_handle: gfx.NameHandle = undefined;
var material_uniform_buffer: gfx.UniformArray(MaterialUniform) = undefined;
var default_texture_handle: gfx.TextureHandle = undefined;

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
) !gfx.TextureHandle {
    if (texture_index) |index| {
        const texture_filename = try std.fmt.allocPrint(
            arena,
            "{s}.{d}.ktx",
            .{
                basename,
                index,
            },
        );

        const relative_path = try std.fs.path.join(
            arena,
            &[_][]const u8{
                dirname,
                texture_filename,
            },
        );
        const texture_path = try getAssetPath(arena, relative_path);

        //log.debug("Base color texture path: {s}", .{texture_path});

        var texture_file = try std.fs.cwd().openFile(texture_path, .{});
        defer texture_file.close();

        const stats = try texture_file.stat();
        const texture_reader = texture_file.reader().any();

        return try gfx.createTextureFromKTX(texture_reader, @intCast(stats.size), .{
            .debug_name = relative_path,
        });
    }

    return default_texture_handle;
}

fn destroyMaterialTexture(
    texture_handle: ?gfx.TextureHandle,
) void {
    if (texture_handle) |handle| {
        if (handle != default_texture_handle)
            gfx.destroyTexture(handle);
    }
}

fn loadPbrMetallicRoughnessMaterial(
    pbr: asset_types.MaterialPbrMetallicRoughness,
    dir: []const u8,
    basename: []const u8,
) !MaterialPbrMetallicRoughness {
    const base_color_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        pbr.base_color_texture_index,
    );
    errdefer destroyMaterialTexture(base_color_texture_handle);

    const metallic_roughness_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        pbr.metallic_roughness_texture_index,
    );
    errdefer destroyMaterialTexture(metallic_roughness_texture_handle);

    return .{
        .base_color_texture_handle = base_color_texture_handle,
        .base_color_factor = pbr.base_color_factor,
        .metallic_roughness_texture_handle = metallic_roughness_texture_handle,
        .metallic_factor = pbr.metallic_factor,
        .roughness_factor = pbr.roughness_factor,
    };
}

fn loadPbrSpecularGlossinessMaterial(
    pbr: asset_types.MaterialPbrSpecularGlossiness,
    dir: []const u8,
    basename: []const u8,
) !MaterialPbrSpecularGlossiness {
    const diffuse_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        pbr.diffuse_texture_index,
    );
    errdefer destroyMaterialTexture(diffuse_texture_handle);

    const specular_glossiness_texture_handle = try loadMaterialTexture(
        dir,
        basename,
        pbr.specular_glossiness_texture_index,
    );
    errdefer destroyMaterialTexture(specular_glossiness_texture_handle);

    return .{
        .diffuse_texture_handle = diffuse_texture_handle,
        .diffuse_factor = pbr.diffuse_factor,
        .specular_glossiness_texture_handle = specular_glossiness_texture_handle,
        .specular_factor = pbr.specular_factor,
        .glossiness_factor = pbr.glossiness_factor,
    };
}

fn updateMaterialUniformBuffer(handle: MaterialHandle) !void {
    const material_data = materials.valuePtr(handle);
    var uniform_data: MaterialUniform = undefined;
    switch (material_data.pbr) {
        .pbr_metallic_roughness => |pbr_value| {
            uniform_data.base_color_factor = pbr_value.base_color_factor;
            uniform_data.metallic_factor = pbr_value.metallic_factor;
            uniform_data.roughness_factor = pbr_value.roughness_factor;
        },
        .pbr_specular_glossiness => |pbr_value| {
            uniform_data.diffuse_factor = pbr_value.diffuse_factor;
            uniform_data.specular_factor = pbr_value.specular_factor;
            uniform_data.glossiness_factor = pbr_value.glossiness_factor;
        },
    }
    uniform_data.emissive_factor = material_data.emissive_factor;

    const ptr: [*]const u8 = @ptrCast(&uniform_data);
    const index = @intFromEnum(handle);
    try material_uniform_buffer.updateFromMemory(index, ptr[0..@sizeOf(MaterialUniform)]);
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(allocator: std.mem.Allocator) !void {
    log.debug("Initializing assets", .{});

    gpa = allocator;

    arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena_impl.deinit();
    defer _ = arena_impl.reset(.retain_capacity);

    arena = arena_impl.allocator();

    mesh_handles = .init();
    errdefer mesh_handles.deinit();

    material_handles = .init();
    errdefer material_handles.deinit();

    assets_path = try getAssetsPath(gpa);
    errdefer allocator.free(assets_path);

    material_uniform_handle = gfx.nameHandle("u_material");

    material_uniform_buffer = try .init(
        MaxMaterialHandles,
        .{ .uniform = true },
        .host,
        .{
            .debug_name = "Materials uniform buffer",
        },
    );
    errdefer material_uniform_buffer.deinit();

    default_texture_handle = try gfx.createTextureFromMemory(
        &[_]u8{ 0xff, 0xff, 0xff, 0xff },
        .{
            .format = .rgba8,
            .width = 1,
            .height = 1,
            .debug_name = "Default empty material texture",
        },
    );
}

pub fn deinit() void {
    log.debug("Deinitializing assets", .{});

    gfx.destroyTexture(default_texture_handle);
    material_uniform_buffer.deinit();

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
        .{
            .debug_name = filename,
        },
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
    log.debug("  - Pipeline layout handle: {any}", .{pipeline_handle});
    log.debug("  - Buffer handle: {any}", .{buffer_handle});

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

    const dir = std.fs.path.dirname(filename) orelse ".";
    const basename = std.fs.path.stem(filename);

    const reader = file.reader().any();

    const handle = material_handles.create();
    errdefer material_handles.destroy(handle);

    const material_data = try readMaterial(arena, reader);

    var pbr: MaterialPbr = undefined;
    if (material_data.pbr_metallic_roughness) |value| {
        pbr = .{
            .pbr_metallic_roughness = try loadPbrMetallicRoughnessMaterial(
                value,
                dir,
                basename,
            ),
        };
    } else if (material_data.pbr_specular_glossiness) |value| {
        pbr = .{
            .pbr_specular_glossiness = try loadPbrSpecularGlossinessMaterial(
                value,
                dir,
                basename,
            ),
        };
    } else {
        return error.InvalidMaterial;
    }

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
        .pbr = pbr,
        .normal_texture_handle = normal_texture_handle,
        .occlusion_texture_handle = occlusion_texture_handle,
        .emissive_texture_handle = emissive_texture_handle,
        .emissive_factor = material_data.emissive_factor,
        .alpha_mode = material_data.alpha_mode,
        .alpha_cutoff = material_data.alpha_cutoff,
        .double_sided = material_data.double_sided,
    });

    try updateMaterialUniformBuffer(handle);

    log.debug("Loaded material: {s}", .{filename});
    switch (pbr) {
        .pbr_metallic_roughness => |pbr_value| {
            log.debug("  - Material type: PBR Metallic/Roughness", .{});
            log.debug("  - Base color texture handle: {any}", .{pbr_value.base_color_texture_handle});
            log.debug("  - Base color factor: [{d}, {d}, {d}, {d}]", .{
                pbr_value.base_color_factor[1],
                pbr_value.base_color_factor[0],
                pbr_value.base_color_factor[2],
                pbr_value.base_color_factor[3],
            });
            log.debug("  - Metallic/Roughness texture handle: {any}", .{pbr_value.metallic_roughness_texture_handle});
            log.debug("  - Metallic factor: {d}", .{pbr_value.metallic_factor});
            log.debug("  - Roughness factor: {d}", .{pbr_value.roughness_factor});
        },
        .pbr_specular_glossiness => |pbr_value| {
            log.debug("  - Material type: PBR Specular/Glossiness", .{});
            log.debug("  - Diffuse texture handle: {any}", .{pbr_value.diffuse_texture_handle});
            log.debug("  - Diffuse factor: [{d}, {d}, {d}, {d}]", .{
                pbr_value.diffuse_factor[0],
                pbr_value.diffuse_factor[1],
                pbr_value.diffuse_factor[2],
                pbr_value.diffuse_factor[3],
            });
            log.debug("  - Specular/Glossiness texture handle: {any}", .{pbr_value.specular_glossiness_texture_handle});
            log.debug("  - Specular factor: [{d}, {d}, {d}]", .{
                pbr_value.specular_factor[0],
                pbr_value.specular_factor[1],
                pbr_value.specular_factor[2],
            });
            log.debug("  - Glossiness factor: {d}", .{pbr_value.glossiness_factor});
        },
    }
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
    switch (material_value.pbr) {
        .pbr_metallic_roughness => |pbr_value| {
            destroyMaterialTexture(pbr_value.base_color_texture_handle);
            destroyMaterialTexture(pbr_value.metallic_roughness_texture_handle);
        },
        .pbr_specular_glossiness => |pbr_value| {
            destroyMaterialTexture(pbr_value.diffuse_texture_handle);
            destroyMaterialTexture(pbr_value.specular_glossiness_texture_handle);
        },
    }
    destroyMaterialTexture(material_value.normal_texture_handle);
    destroyMaterialTexture(material_value.occlusion_texture_handle);
    destroyMaterialTexture(material_value.emissive_texture_handle);
    material_handles.destroy(handle);
}

pub inline fn material(handle: MaterialHandle) *Material {
    return materials.valuePtr(handle);
}

pub inline fn materialUniformHandle() gfx.NameHandle {
    return material_uniform_handle;
}

pub inline fn materialUniformBufferHandle() gfx.BufferHandle {
    return material_uniform_buffer.handle;
}

pub inline fn materialUniformBufferOffset(handle: MaterialHandle) u32 {
    return material_uniform_buffer.offset(@intFromEnum(handle));
}
