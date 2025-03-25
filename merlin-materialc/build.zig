const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // *********************************************************************************************
    // Dependencies
    // *********************************************************************************************

    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_assets = b.dependency("merlin_assets", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_ktx = b.dependency("merlin_ktx", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_image = b.dependency("merlin_image", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_texturec = b.dependency("merlin_texturec", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_gltf = b.dependency("merlin_gltf", .{
        .target = target,
        .optimize = optimize,
    });
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    // *********************************************************************************************
    // Library
    // *********************************************************************************************

    const materialc_mod = b.addModule("merlin_materialc", .{
        .root_source_file = b.path("src/materialc.zig"),
        .target = target,
        .optimize = optimize,
    });

    materialc_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    materialc_mod.addImport("merlin_assets", merlin_assets.module("merlin_assets"));
    materialc_mod.addImport("merlin_ktx", merlin_ktx.module("merlin_ktx"));
    materialc_mod.addImport("merlin_texturec", merlin_texturec.module("merlin_texturec"));
    materialc_mod.addImport("merlin_gltf", merlin_gltf.module("merlin_gltf"));
    materialc_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const materialc = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin_materialc",
        .root_module = materialc_mod,
    });
    b.installArtifact(materialc);

    // *********************************************************************************************
    // Executable
    // *********************************************************************************************

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("materialc", materialc_mod);
    exe_mod.addImport("clap", clap.module("clap"));
    exe_mod.addImport("merlin_gltf", merlin_gltf.module("merlin_gltf"));
    exe_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const exe = b.addExecutable(.{
        .name = "materialc",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // *********************************************************************************************
    // Run
    // *********************************************************************************************

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
