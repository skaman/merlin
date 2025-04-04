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

    const geometryc_mod = b.addModule("merlin_geometryc", .{
        .root_source_file = b.path("src/geometryc.zig"),
        .target = target,
        .optimize = optimize,
    });

    geometryc_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    geometryc_mod.addImport("merlin_gltf", merlin_gltf.module("merlin_gltf"));

    const geometryc = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin_geometryc",
        .root_module = geometryc_mod,
    });
    b.installArtifact(geometryc);

    // *********************************************************************************************
    // Executable
    // *********************************************************************************************

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("geometryc", geometryc_mod);
    exe_mod.addImport("clap", clap.module("clap"));
    exe_mod.addImport("merlin_gltf", merlin_gltf.module("merlin_gltf"));
    exe_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));

    const exe = b.addExecutable(.{
        .name = "geometryc",
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
