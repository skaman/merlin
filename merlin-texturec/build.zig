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
    const merlin_ktx = b.dependency("merlin_ktx", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_image = b.dependency("merlin_image", .{
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

    const texturec_mod = b.createModule(.{
        .root_source_file = b.path("src/texturec.zig"),
        .target = target,
        .optimize = optimize,
    });

    texturec_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    texturec_mod.addImport("merlin_ktx", merlin_ktx.module("merlin_ktx"));
    texturec_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const texturec = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin-texturec",
        .root_module = texturec_mod,
    });
    b.installArtifact(texturec);

    // *********************************************************************************************
    // Executable
    // *********************************************************************************************

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("texturec", texturec_mod);
    exe_mod.addImport("clap", clap.module("clap"));
    exe_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const exe = b.addExecutable(.{
        .name = "texturec",
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
