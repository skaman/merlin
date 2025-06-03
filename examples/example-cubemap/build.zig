const std = @import("std");
const builtin = @import("builtin");

const geometryc = @import("merlin_geometryc");
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

    const example_cubemap_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_cubemap = b.addExecutable(.{
        .name = "example_cubemap",
        .root_module = example_cubemap_mod,
    });

    try shaderc.compile(b, &[_]shaderc.Shader{
        .{
            .input_file = "assets/skybox.vert",
            .output_file = "assets/skybox.vert.bin",
        },
        .{
            .input_file = "assets/skybox.frag",
            .output_file = "assets/skybox.frag.bin",
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

    try geometryc.compile(b, &[_]geometryc.Mesh{
        .{
            .source = "assets/cube.gltf",
            .output = "assets/cube.mesh",
        },
    });

    b.installArtifact(example_cubemap);
    example_cubemap.root_module.addImport("mini_engine", mini_engine_dep.module("mini_engine"));

    const run_cmd = b.addRunArtifact(example_cubemap);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
