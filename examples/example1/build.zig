const std = @import("std");
const builtin = @import("builtin");

fn addShaders(
    b: *std.Build,
    shaders: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !void {
    const merlin_shaderc = b.dependency("merlin_shaderc", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_shaderc_exe = merlin_shaderc.artifact("merlin-shaderc");

    for (shaders) |shader| {
        var output_buffer: [4096]u8 = undefined;
        const output_slice = try std.fmt.bufPrint(&output_buffer, "{s}.bin", .{shader});

        const tool_step = b.addRunArtifact(merlin_shaderc_exe);
        tool_step.addArg("-o");
        const output = tool_step.addOutputFileArg(output_slice);
        tool_step.addFileArg(b.path(shader));

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .bin, output_slice).step);
    }
}

fn addTextures(
    b: *std.Build,
    textures: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) !void {
    const merlin_texturec = b.dependency("merlin_texturec", .{
        .target = target,
        .optimize = optimize,
    });
    const merlin_texturec_exe = merlin_texturec.artifact("merlin-texturec");

    for (textures) |texture| {
        var output_buffer: [4096]u8 = undefined;
        const extension = std.fs.path.extension(texture);
        const texture_without_extension = texture[0..(texture.len - extension.len)];
        const output_slice = try std.fmt.bufPrint(&output_buffer, "{s}.ktx", .{texture_without_extension});

        const tool_step = b.addRunArtifact(merlin_texturec_exe);
        tool_step.addArg("-m");
        tool_step.addArg("-c");
        tool_step.addFileArg(b.path(texture));
        const output = tool_step.addOutputFileArg(output_slice);

        b.getInstallStep().dependOn(&b.addInstallFileWithDir(output, .bin, output_slice).step);
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merlin_core_layer = b.dependency("merlin_core_layer", .{
        .target = target,
        .optimize = optimize,
    });

    const example1_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example1 = b.addExecutable(.{
        .name = "example1",
        .root_module = example1_mod,
    });

    const shaders = [_][]const u8{
        "assets/shader.vert",
        "assets/shader.frag",
    };
    try addShaders(b, &shaders, target, optimize);

    const textures = [_][]const u8{
        "assets/uv_texture.png",
    };
    try addTextures(b, &textures, target, optimize);

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
