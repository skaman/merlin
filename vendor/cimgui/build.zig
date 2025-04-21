const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("cimgui", .{});

    const lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = target,
        .optimize = optimize,
    });

    lib.addCSourceFiles(.{
        .files = &.{
            "upstream/cimgui.cpp",
            "upstream/imgui/imgui.cpp",
            "upstream/imgui/imgui_draw.cpp",
            "upstream/imgui/imgui_widgets.cpp",
            "upstream/imgui/imgui_tables.cpp",
            "upstream/imgui/imgui_demo.cpp",
        },
        .flags = &.{
            // "-std=c99",
            // "-fno-sanitize=undefined",
        },
    });
    lib.linkLibC();
    lib.linkLibCpp();

    lib.addIncludePath(b.path("upstream"));

    b.installArtifact(lib);
}
