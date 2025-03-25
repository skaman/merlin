const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_utils = b.dependency("merlin_utils", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_assets_mod = b.addModule("merlin_assets", .{
        .root_source_file = b.path("src/assets.zig"),
        .target = target,
        .optimize = optimize,
    });

    merlin_assets_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));

    const merlin_assets = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin_assets",
        .root_module = merlin_assets_mod,
    });
    b.installArtifact(merlin_assets);
}
