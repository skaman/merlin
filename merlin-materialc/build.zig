const std = @import("std");
const builtin = @import("builtin");

pub const Material = struct {
    source: []const u8,
    output: []const u8,
    compression: bool = false,
    level: ?usize = null,
    quality: ?usize = null,
    mipmaps: bool = false,
    edge: ?[]const u8 = null,
    filter: ?[]const u8 = null,
};

pub fn compile(b: *std.Build, materials: []const Material) !void {
    const merlin_materialc = b.dependency("merlin_materialc", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const materialc_exe = merlin_materialc.artifact("materialc");

    for (materials) |material| {
        const tool_step = b.addRunArtifact(materialc_exe);
        if (material.compression) {
            tool_step.addArg("-c");
        }
        if (material.level) |level| {
            var level_buf: [16]u8 = undefined;
            const level_slice = try std.fmt.bufPrint(
                &level_buf,
                "{d}",
                .{level},
            );
            tool_step.addArg("-l");
            tool_step.addArg(level_slice);
        }
        if (material.quality) |quality| {
            var quality_buf: [16]u8 = undefined;
            const quality_slice = try std.fmt.bufPrint(
                &quality_buf,
                "{d}",
                .{quality},
            );
            tool_step.addArg("-q");
            tool_step.addArg(quality_slice);
        }
        if (material.mipmaps) {
            tool_step.addArg("-m");
        }
        if (material.edge) |edge| {
            tool_step.addArg("-e");
            tool_step.addArg(edge);
        }
        if (material.filter) |filter| {
            tool_step.addArg("-f");
            tool_step.addArg(filter);
        }
        tool_step.addFileArg(b.path(material.source));
        const output = tool_step.addOutputDirectoryArg(material.output);

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = output,
            .install_dir = .bin,
            .install_subdir = material.output,
        }).step);
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // *********************************************************************************************
    // Dependencies
    // *********************************************************************************************

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
    const merlin_texturec = b.dependency("merlin_texturec", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_gltf = b.dependency("merlin_gltf", .{
        .target = target,
        .optimize = optimize,
    });
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    // *********************************************************************************************
    // Library
    // *********************************************************************************************

    const materialc_mod = b.addModule("merlin_materialc", .{
        .root_source_file = b.path("src/materialc.zig"),
        .target = target,
        .optimize = optimize,
    });

    materialc_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    materialc_mod.addImport("merlin_ktx", merlin_ktx.module("merlin_ktx"));
    materialc_mod.addImport("merlin_texturec", merlin_texturec.module("merlin_texturec"));
    materialc_mod.addImport("merlin_gltf", merlin_gltf.module("merlin_gltf"));
    materialc_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const materialc = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin_materialc",
        .root_module = materialc_mod,
    });
    b.installArtifact(materialc);

    // *********************************************************************************************
    // Executable
    // *********************************************************************************************

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("materialc", materialc_mod);
    exe_mod.addImport("clap", clap.module("clap"));
    exe_mod.addImport("merlin_gltf", merlin_gltf.module("merlin_gltf"));
    exe_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const exe = b.addExecutable(.{
        .name = "materialc",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    // *********************************************************************************************
    // Run
    // *********************************************************************************************

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run");
    run_step.dependOn(&run_cmd.step);
}
