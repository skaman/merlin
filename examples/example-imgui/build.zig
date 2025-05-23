const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mini_engine_dep = b.dependency("mini_engine", .{
        .target = target,
        .optimize = optimize,
    });

    const example_imgui_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_imgui = b.addExecutable(.{
        .name = "example_imgui",
        .root_module = example_imgui_mod,
    });

    b.installArtifact(example_imgui);
    example_imgui.root_module.addImport("mini_engine", mini_engine_dep.module("mini_engine"));

    const run_cmd = b.addRunArtifact(example_imgui);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
