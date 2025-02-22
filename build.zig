const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //--------------------------------------------------------------------------------------------------
    // dependencies
    //--------------------------------------------------------------------------------------------------
    const glfw = b.dependency("glfw", .{});
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const libshaderc = b.dependency("libshaderc", .{});
    const clap = b.dependency("clap", .{});

    //--------------------------------------------------------------------------------------------------
    // engine
    //--------------------------------------------------------------------------------------------------
    const engine_exe_mod = b.createModule(.{
        .root_source_file = b.path("engine/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const engine_exe = b.addExecutable(.{
        .name = "engine",
        .root_module = engine_exe_mod,
    });
    b.installArtifact(engine_exe);
    engine_exe.linkLibC();
    engine_exe.linkLibrary(glfw.artifact("glfw"));
    engine_exe.linkLibrary(vulkan_headers.artifact("vulkan_headers"));

    const engine_run_cmd = b.addRunArtifact(engine_exe);
    engine_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        engine_run_cmd.addArgs(args);
    }

    const run_step = b.step("run_engine", "Run the engine");
    run_step.dependOn(&engine_run_cmd.step);

    //--------------------------------------------------------------------------------------------------
    // shaderc
    //--------------------------------------------------------------------------------------------------
    const shaderc_exe_mod = b.createModule(.{
        .root_source_file = b.path("shaderc/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shaderc_exe = b.addExecutable(.{
        .name = "shaderc",
        .root_module = shaderc_exe_mod,
    });
    b.installArtifact(shaderc_exe);
    shaderc_exe.linkLibC();
    shaderc_exe.linkLibrary(libshaderc.artifact("libshaderc"));
    shaderc_exe.root_module.addImport("clap", clap.module("clap"));

    const shaderc_run_cmd = b.addRunArtifact(shaderc_exe);
    shaderc_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        shaderc_run_cmd.addArgs(args);
    }

    const shaderc_run_step = b.step("run_shaderc", "Run shaderc");
    shaderc_run_step.dependOn(&shaderc_run_cmd.step);

    //--------------------------------------------------------------------------------------------------
    // checks
    //--------------------------------------------------------------------------------------------------
    const check = b.step("check", "Check if the projects compiles");
    check.dependOn(&engine_exe.step);
    check.dependOn(&shaderc_exe.step);
}
