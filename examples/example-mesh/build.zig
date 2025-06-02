const std = @import("std");
const builtin = @import("builtin");

const mini_engine = @import("mini_engine");
const texturec = @import("merlin_texturec");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mini_engine_dep = b.dependency("mini_engine", .{
        .target = target,
        .optimize = optimize,
    });

    const example_mesh_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_mesh = b.addExecutable(.{
        .name = "example_mesh",
        .root_module = example_mesh_mod,
    });

    try mini_engine.addShaders(b, &[_][]const u8{
        "assets/shader.vert",
        "assets/shader.frag",
    });

    try texturec.compile(b, &[_]texturec.Texture{
        .{
            .input_files = &[_][]const u8{"assets/uv_texture.png"},
            .output_file = "assets/uv_texture.ktx",
            .compression = true,
            .mipmaps = true,
        },
    });

    try mini_engine.addMeshes(b, &[_]mini_engine.SourceMesh{
        .{
            .source = "assets/Box/Box.gltf",
            .output = "assets/box.0.mesh",
            .tex_coord = false,
        },
        .{
            .source = "assets/BoxTextured/BoxTextured.gltf",
            .output = "assets/box-textured.0.mesh",
        },
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.0.mesh",
            .sub_mesh = 0,
        },
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.1.mesh",
            .sub_mesh = 1,
        },
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.2.mesh",
            .sub_mesh = 2,
        },
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.3.mesh",
            .sub_mesh = 3,
        },
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.4.mesh",
            .sub_mesh = 4,
        },
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/flight-helmet.5.mesh",
            .sub_mesh = 5,
        },
    });

    try mini_engine.addMaterials(b, &[_]mini_engine.SourceMaterial{
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/FlightHelmet",
        },
        .{
            .source = "assets/BoxTextured/BoxTextured.gltf",
            .output = "assets/BoxTextured",
        },
    });

    b.installArtifact(example_mesh);
    example_mesh.root_module.addImport("mini_engine", mini_engine_dep.module("mini_engine"));

    const run_cmd = b.addRunArtifact(example_mesh);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
