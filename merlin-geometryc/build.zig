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

    const geometryc_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const geometryc = b.addExecutable(.{
        .name = "merlin-geometryc",
        .root_module = geometryc_mod,
    });
    b.installArtifact(geometryc);

    geometryc.root_module.addImport("merlin_core_layer", merlin_core_layer.module("merlin_core_layer"));
    geometryc.root_module.addImport("clap", clap.module("clap"));

    const run_cmd = b.addRunArtifact(geometryc);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
