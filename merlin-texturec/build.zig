const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const texturec_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const texturec = b.addExecutable(.{
        .name = "merlin-texturec",
        .root_module = texturec_mod,
    });
    b.installArtifact(texturec);

    texturec.root_module.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    texturec.root_module.addImport("merlin_ktx", merlin_ktx.module("merlin_ktx"));
    texturec.root_module.addImport("merlin_image", merlin_image.module("merlin_image"));
    texturec.root_module.addImport("clap", clap.module("clap"));

    const run_cmd = b.addRunArtifact(texturec);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
