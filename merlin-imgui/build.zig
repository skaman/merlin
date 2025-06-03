const std = @import("std");
const builtin = @import("builtin");

const shaderc = @import("merlin_shaderc");

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
    try shaderc.compileEmbed(b, &[_]shaderc.Shader{
        .{
            .input_file = "src/shaders/imgui.vert",
            .output_file = "src/shaders/imgui.vert.bin",
        },
        .{
            .input_file = "src/shaders/imgui.frag",
            .output_file = "src/shaders/imgui.frag.bin",
        },
    }, merlin_imgui);

    b.installArtifact(merlin_imgui);

    merlin_imgui.linkLibrary(cimgui.artifact("cimgui"));
    merlin_imgui.addIncludePath(b.path("../vendor/cimgui/upstream"));
}
