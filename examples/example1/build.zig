const std = @import("std");
const builtin = @import("builtin");

fn addShaders(
    b: *std.Build,
    shaders: []const []const u8,
) !void {
    const merlin_shaderc = b.dependency("merlin_shaderc", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const merlin_shaderc_exe = merlin_shaderc.artifact("shaderc");

    for (shaders) |shader| {
        var output_buffer: [4096]u8 = undefined;
        const output_slice = try std.fmt.bufPrint(&output_buffer, "{s}.bin", .{shader});

        const tool_step = b.addRunArtifact(merlin_shaderc_exe);
        tool_step.addFileArg(b.path(shader));
        const output = tool_step.addOutputFileArg(output_slice);

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .bin, output_slice).step);
    }
}

fn addTextures(
    b: *std.Build,
    textures: []const []const u8,
) !void {
    const merlin_texturec = b.dependency("merlin_texturec", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const merlin_texturec_exe = merlin_texturec.artifact("texturec");

    for (textures) |texture| {
        var output_buffer: [4096]u8 = undefined;
        const extension = std.fs.path.extension(texture);
        const texture_without_extension = texture[0..(texture.len - extension.len)];
        const output_slice = try std.fmt.bufPrint(&output_buffer, "{s}.ktx", .{texture_without_extension});

        const tool_step = b.addRunArtifact(merlin_texturec_exe);
        tool_step.addArg("-m");
        tool_step.addArg("-c");
        tool_step.addFileArg(b.path(texture));
        const output = tool_step.addOutputFileArg(output_slice);

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .bin, output_slice).step);
    }
}

const SourceMesh = struct {
    source: []const u8,
    output: []const u8,
    sub_mesh: u32 = 0,
    normal: bool = true,
    tangent: bool = false,
    color: bool = false,
    weight: bool = false,
    tex_coord: bool = true,
};

fn addMeshes(
    b: *std.Build,
    meshes: []const SourceMesh,
) !void {
    const merlin_geometryc = b.dependency("merlin_geometryc", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const geometryc_exe = merlin_geometryc.artifact("geometryc");

    for (meshes) |mesh| {
        const sub_mesh = try std.fmt.allocPrint(b.allocator, "{d}", .{mesh.sub_mesh});
        defer b.allocator.free(sub_mesh);
        const tool_step = b.addRunArtifact(geometryc_exe);
        tool_step.addArg("-s");
        tool_step.addArg(sub_mesh);
        tool_step.addArg("-n");
        tool_step.addArg(if (mesh.normal) "1" else "0");
        tool_step.addArg("-t");
        tool_step.addArg(if (mesh.tangent) "1" else "0");
        tool_step.addArg("-C");
        tool_step.addArg(if (mesh.color) "1" else "0");
        tool_step.addArg("-w");
        tool_step.addArg(if (mesh.weight) "1" else "0");
        tool_step.addArg("-T");
        tool_step.addArg(if (mesh.tex_coord) "1" else "0");
        tool_step.addFileArg(b.path(mesh.source));
        const output = tool_step.addOutputFileArg(mesh.output);

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .bin, mesh.output).step);
    }
}

const SourceMaterial = struct {
    source: []const u8,
    output: []const u8,
};

fn addMaterials(
    b: *std.Build,
    materials: []const SourceMaterial,
) !void {
    const merlin_materialc = b.dependency("merlin_materialc", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const materialc_exe = merlin_materialc.artifact("materialc");

    for (materials) |material| {
        const tool_step = b.addRunArtifact(materialc_exe);
        tool_step.addArg("-m");
        tool_step.addArg("-c");
        tool_step.addFileArg(b.path(material.source));
        const output = tool_step.addOutputDirectoryArg(material.output);

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = output,
            .install_dir = .bin,
            .install_subdir = material.output,
        }).step);
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_platform = b.dependency("merlin_platform", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_gfx = b.dependency("merlin_gfx", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_assets = b.dependency("merlin_assets", .{
        .target = target,
        .optimize = optimize,
    });

    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    const example1_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example1 = b.addExecutable(.{
        .name = "example1",
        .root_module = example1_mod,
    });

    try addShaders(b, &[_][]const u8{
        "assets/shader.vert",
        "assets/shader.frag",
    });

    try addTextures(b, &[_][]const u8{
        "assets/uv_texture.png",
    });

    try addMeshes(b, &[_]SourceMesh{
        SourceMesh{
            .source = "assets/Box/Box.gltf",
            .output = "assets/box.0.mesh",
            .tex_coord = false,
        },
        SourceMesh{
            .source = "assets/BoxTextured/BoxTextured.gltf",
            .output = "assets/box-textured.0.mesh",
        },
        SourceMesh{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.0.mesh",
            .sub_mesh = 0,
        },
        SourceMesh{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.1.mesh",
            .sub_mesh = 1,
        },
        SourceMesh{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.2.mesh",
            .sub_mesh = 2,
        },
        SourceMesh{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.3.mesh",
            .sub_mesh = 3,
        },
        SourceMesh{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.4.mesh",
            .sub_mesh = 4,
        },
        SourceMesh{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.5.mesh",
            .sub_mesh = 5,
        },
    });

    try addMaterials(b, &[_]SourceMaterial{
        SourceMaterial{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/FlightHelmet",
        },
        SourceMaterial{
            .source = "assets/BoxTextured/BoxTextured.gltf",
            .output = "assets/BoxTextured",
        },
    });

    b.installArtifact(example1);
    example1.root_module.addImport("merlin_platform", merlin_platform.module("merlin_platform"));
    example1.root_module.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    example1.root_module.addImport("merlin_gfx", merlin_gfx.module("merlin_gfx"));
    example1.root_module.addImport("merlin_assets", merlin_assets.module("merlin_assets"));
    example1.root_module.addImport("zmath", zmath.module("root"));

    const run_cmd = b.addRunArtifact(example1);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
