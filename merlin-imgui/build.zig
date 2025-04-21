const std = @import("std");
const builtin = @import("builtin");

fn addShaders(
    b: *std.Build,
    shaders: []const []const u8,
    exe: *std.Build.Step.Compile,
) !void {
    const merlin_shaderc = b.dependency("merlin_shaderc", .{
        .optimize = std.builtin.OptimizeMode.ReleaseFast,
    });
    const merlin_shaderc_exe = merlin_shaderc.artifact("shaderc");

    for (shaders) |shader| {
        var output_buffer: [4096]u8 = undefined;
        const output_slice = try std.fmt.bufPrint(&output_buffer, "{s}.bin", .{shader});

        const tool_step = b.addRunArtifact(merlin_shaderc_exe);
        tool_step.addFileArg(b.path(shader));
        const output = tool_step.addOutputFileArg(output_slice);

        exe.root_module.addAnonymousImport(std.fs.path.basename(output_slice), .{
            .root_source_file = output,
        });
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const merling_platform = b.dependency("merlin_platform", .{
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
    const cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    const merlin_imgui_mod = b.addModule("merlin_imgui", .{
        .root_source_file = b.path("src/imgui.zig"),
        .target = target,
        .optimize = optimize,
    });

    merlin_imgui_mod.addImport("merlin_platform", merling_platform.module("merlin_platform"));
    merlin_imgui_mod.addImport("merlin_utils", merlin_utils.module("merlin_utils"));
    merlin_imgui_mod.addImport("merlin_gfx", merlin_gfx.module("merlin_gfx"));

    const merlin_imgui = b.addLibrary(.{
        .linkage = .static,
        .name = "merlin_imgui",
        .root_module = merlin_imgui_mod,
    });

    const shaders = [_][]const u8{
        "src/shaders/imgui.vert",
        "src/shaders/imgui.frag",
    };
    try addShaders(b, &shaders, merlin_imgui);

    b.installArtifact(merlin_imgui);

    merlin_imgui.linkLibrary(cimgui.artifact("cimgui"));
    merlin_imgui.addIncludePath(b.path("../vendor/cimgui/upstream"));
}
