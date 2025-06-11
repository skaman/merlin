const std = @import("std");
const builtin = @import("builtin");

const geometryc = @import("merlin_geometryc");
const materialc = @import("merlin_materialc");
const mini_engine = @import("mini_engine");
const shaderc = @import("merlin_shaderc");
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

    try shaderc.compile(b, &[_]shaderc.Shader{
        .{
            .input_file = "assets/shader.vert",
            .output_file = "assets/shader.vert.bin",
        },
        .{
            .input_file = "assets/shader.frag",
            .output_file = "assets/shader.frag.bin",
        },
        .{
            .input_file = "assets/skybox.vert",
            .output_file = "assets/skybox.vert.bin",
        },
        .{
            .input_file = "assets/skybox.frag",
            .output_file = "assets/skybox.frag.bin",
        },
    });

    try geometryc.compile(b, &[_]geometryc.Mesh{
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
        .{
            .source = "assets/cube.gltf",
            .output = "assets/cube.mesh",
        },
    });

    try texturec.compile(b, &[_]texturec.Texture{
        .{
            .input_files = &[_][]const u8{
                "assets/Meadow/posx.jpg",
                "assets/Meadow/negx.jpg",
                "assets/Meadow/posy.jpg",
                "assets/Meadow/negy.jpg",
                "assets/Meadow/posz.jpg",
                "assets/Meadow/negz.jpg",
            },
            .output_file = "assets/cubemap.ktx",
            .compression = true,
            .mipmaps = true,
            .cubemap = true,
        },
    });

    try materialc.compile(b, &[_]materialc.Material{
        .{
            .source = "assets/FlightHelmet/FlightHelmet.gltf",
            .output = "assets/FlightHelmet",
            .compression = true,
            .mipmaps = true,
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
