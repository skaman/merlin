const std = @import("std");
const builtin = @import("builtin");

pub const Texture = struct {
    input_files: []const []const u8,
    output_file: []const u8,
    compression: bool = false,
    normalmap: bool = false,
    level: ?usize = null,
    quality: ?usize = null,
    mipmaps: bool = false,
    edge: ?[]const u8 = null,
    filter: ?[]const u8 = null,
    cubemap: bool = false,
};

pub fn compile(
    b: *std.Build,
    textures: []const Texture,
) !void {
    const merlin_texturec = b.dependency("merlin_texturec", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const merlin_texturec_exe = merlin_texturec.artifact("texturec");

    for (textures) |texture| {
        const tool_step = b.addRunArtifact(merlin_texturec_exe);
        if (texture.compression) {
            tool_step.addArg("-c");
        }
        if (texture.normalmap) {
            tool_step.addArg("-n");
        }
        if (texture.level) |level| {
            var level_buf: [16]u8 = undefined;
            const level_slice = try std.fmt.bufPrint(
                &level_buf,
                "{d}",
                .{level},
            );
            tool_step.addArg("-l");
            tool_step.addArg(level_slice);
        }
        if (texture.quality) |quality| {
            var quality_buf: [16]u8 = undefined;
            const quality_slice = try std.fmt.bufPrint(
                &quality_buf,
                "{d}",
                .{quality},
            );
            tool_step.addArg("-q");
            tool_step.addArg(quality_slice);
        }
        if (texture.mipmaps) {
            tool_step.addArg("-m");
        }
        if (texture.edge) |edge| {
            tool_step.addArg("-e");
            tool_step.addArg(edge);
        }
        if (texture.filter) |filter| {
            tool_step.addArg("-f");
            tool_step.addArg(filter);
        }
        if (texture.cubemap) {
            tool_step.addArg("-C");
        }
        tool_step.addArg("-o");
        const output = tool_step.addOutputFileArg(texture.output_file);
        for (texture.input_files) |input_file| {
            tool_step.addFileArg(b.path(input_file));
        }

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(
            output,
            .bin,
            texture.output_file,
        ).step);
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

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    // *********************************************************************************************
    // Library
    // *********************************************************************************************

    const texturec_mod = b.addModule("merlin_texturec", .{
        .root_source_file = b.path("src/texturec.zig"),
        .target = target,
        .optimize = optimize,
    });

    texturec_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    texturec_mod.addImport("merlin_ktx", merlin_ktx.module("merlin_ktx"));
    texturec_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const texturec = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin_texturec",
        .root_module = texturec_mod,
    });
    b.installArtifact(texturec);

    // *********************************************************************************************
    // Executable
    // *********************************************************************************************

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("texturec", texturec_mod);
    exe_mod.addImport("clap", clap.module("clap"));
    exe_mod.addImport("merlin_image", merlin_image.module("merlin_image"));

    const exe = b.addExecutable(.{
        .name = "texturec",
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
