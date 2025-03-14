const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_core_layer = b.dependency("merlin_core_layer", .{
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

    const shaderc_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shaderc = b.addExecutable(.{
        .name = "merlin-shaderc",
        .root_module = shaderc_mod,
    });
    b.installArtifact(shaderc);

    shaderc.linkLibC();
    shaderc.linkLibrary(libshaderc.artifact("libshaderc"));
    shaderc.addIncludePath(b.path("../vendor/shaderc/upstream/libshaderc/include"));
    shaderc.linkLibrary(spirv_reflect.artifact("spirv_reflect"));
    shaderc.addIncludePath(b.path("../vendor/spirv-reflect/upstream"));

    shaderc.root_module.addImport("merlin_core_layer", merlin_core_layer.module("merlin_core_layer"));
    shaderc.root_module.addImport("clap", clap.module("clap"));

    const run_cmd = b.addRunArtifact(shaderc);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
