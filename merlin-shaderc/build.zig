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
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const libshaderc = b.dependency("libshaderc", .{
        .target = target,
        .optimize = optimize,
    });
    const spirv_reflect = b.dependency("spirv_reflect", .{
        .target = target,
        .optimize = optimize,
    });

    // *********************************************************************************************
    // Library
    // *********************************************************************************************

    const shaderc_mod = b.createModule(.{
        .root_source_file = b.path("src/shaderc.zig"),
        .target = target,
        .optimize = optimize,
    });

    shaderc_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));

    const shaderc = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin-shaderc",
        .root_module = shaderc_mod,
    });
    b.installArtifact(shaderc);

    shaderc.linkLibrary(libshaderc.artifact("libshaderc"));
    shaderc.addIncludePath(b.path("../vendor/shaderc/upstream/libshaderc/include"));
    shaderc.linkLibrary(spirv_reflect.artifact("spirv_reflect"));
    shaderc.addIncludePath(b.path("../vendor/spirv-reflect/upstream"));

    // *********************************************************************************************
    // Executable
    // *********************************************************************************************

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("shaderc", shaderc_mod);
    exe_mod.addImport("clap", clap.module("clap"));

    const exe = b.addExecutable(.{
        .name = "shaderc",
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
