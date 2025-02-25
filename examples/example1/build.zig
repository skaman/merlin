const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_core_layer = b.dependency("merlin_core_layer", .{});

    const example1_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example1 = b.addExecutable(.{
        .name = "example1",
        .root_module = example1_mod,
    });
    b.installArtifact(example1);
    example1.root_module.addImport("merlin_core_layer", merlin_core_layer.module("merlin_core_layer"));

    const run_cmd = b.addRunArtifact(example1);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
