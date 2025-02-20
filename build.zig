const std = @import("std");
const builtin = @import("builtin");

const glfw_build = @import("vendor/glfw-build.zig");
const glslang_build = @import("vendor/glslang-build.zig");
const spirv_tools_build = @import("vendor/spirv-tools-build.zig");
const vulkan_headers_build = @import("vendor/vulkan-headers-build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        .enable_x11 = b.option(
            bool,
            "x11",
            "Whether to build with X11 support (default: true)",
        ) orelse true,
        .enable_wayland = b.option(
            bool,
            "wayland",
            "Whether to build with Wayland support (default: true)",
        ) orelse true,
    };

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "z3dfx",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
    exe.linkLibC();

    const shaderc_exe_mod = b.createModule(.{
        .root_source_file = b.path("shaderc/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shaderc_exe = b.addExecutable(.{
        .name = "shaderc",
        .root_module = shaderc_exe_mod,
    });
    b.installArtifact(shaderc_exe);
    shaderc_exe.linkLibC();

    // VULKAN HEADERS
    vulkan_headers_build.linkLibrary(b, exe);

    // GLFW
    const glfw = glfw_build.addLibrary(b, target, optimize, options.enable_x11, options.enable_wayland);
    glfw_build.linkLibrary(b, exe, glfw);

    const spirv_tools = spirv_tools_build.addLibrary(b, target, optimize);
    spirv_tools_build.linkLibrary(b, shaderc_exe, spirv_tools);

    const glslang = glslang_build.addLibrary(b, target, optimize, spirv_tools);
    glslang_build.linkLibrary(b, exe, glslang);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const shaderc_run_cmd = b.addRunArtifact(shaderc_exe);
    shaderc_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        shaderc_run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const shaderc_run_step = b.step("shaderc_run", "Run the shaderc app");
    shaderc_run_step.dependOn(&shaderc_run_cmd.step);

    const check = b.step("check", "Check if z3dfx compiles");
    check.dependOn(&exe.step);
}
