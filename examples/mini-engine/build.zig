const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_platform = b.dependency("merlin_platform", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_gfx = b.dependency("merlin_gfx", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_imgui = b.dependency("merlin_imgui", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_assets = b.dependency("merlin_assets", .{
        .target = target,
        .optimize = optimize,
    });

    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
    });

    const mini_engine_mod = b.addModule("mini_engine", .{
        .root_source_file = b.path("src/mini_engine.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mini_engine = b.addLibrary(.{
        .linkage = .static,
        .name = "mini_engine",
        .root_module = mini_engine_mod,
    });
    b.installArtifact(mini_engine);

    mini_engine.root_module.addImport("merlin_platform", merlin_platform.module("merlin_platform"));
    mini_engine.root_module.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    mini_engine.root_module.addImport("merlin_gfx", merlin_gfx.module("merlin_gfx"));
    mini_engine.root_module.addImport("merlin_imgui", merlin_imgui.module("merlin_imgui"));
    mini_engine.root_module.addImport("merlin_assets", merlin_assets.module("merlin_assets"));
    mini_engine.root_module.addImport("zmath", zmath.module("root"));

    const run_cmd = b.addRunArtifact(mini_engine);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
