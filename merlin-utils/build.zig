const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_utils_mod = b.addModule("merlin_utils", .{
        .root_source_file = b.path("src/utils.zig"),
        .target = target,
        .optimize = optimize,
    });

    const merlin_utils = b.addLibrary(.{
        .name = "merlin_utils",
        .root_module = merlin_utils_mod,
    });
    b.installArtifact(merlin_utils);
}
