const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_core_layer = b.dependency("merlin_core_layer", .{});
    const clap = b.dependency("clap", .{});
    const stb = b.dependency("stb", .{});
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const ktx_software = b.dependency("ktx_software", .{});

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

    texturec.root_module.addImport("merlin_core_layer", merlin_core_layer.module("merlin_core_layer"));
    texturec.root_module.addImport("clap", clap.module("clap"));

    texturec.linkLibrary(stb.artifact("stb"));
    texturec.addIncludePath(b.path("../vendor/stb/upstream"));

    texturec.linkLibrary(ktx_software.artifact("ktx_software"));
    texturec.addIncludePath(b.path("../vendor/ktx-software/upstream/include"));

    texturec.linkLibrary(vulkan_headers.artifact("vulkan_headers"));
    texturec.addIncludePath(b.path("../vendor/vulkan-headers/upstream/include"));

    const run_cmd = b.addRunArtifact(texturec);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
