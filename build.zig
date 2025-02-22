const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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

    const glfw = b.dependency("glfw", .{});
    exe.linkLibrary(glfw.artifact("glfw"));

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    exe.linkLibrary(vulkan_headers.artifact("vulkan_headers"));

    //const glfw = glfw_build.addLibrary(b, target, optimize, options.enable_x11, options.enable_wayland);
    //glfw_build.linkLibrary(b, exe, glfw);

    //const spirv_tools = spirv_tools_build.addLibrary(b, target, optimize);
    //spirv_tools_build.linkLibrary(b, shaderc_exe, spirv_tools);

    //const glslang = glslang_build.addLibrary(b, target, optimize, spirv_tools);
    //glslang_build.linkLibrary(b, shaderc_exe, glslang);

    //const libshaderc = libshaderc_build.addLibrary(b, target, optimize, spirv_tools, glslang);
    //libshaderc_build.linkLibrary(b, shaderc_exe, libshaderc);

    const libshaderc = b.dependency("libshaderc", .{});
    shaderc_exe.linkLibrary(libshaderc.artifact("libshaderc"));

    const clap = b.dependency("clap", .{});
    shaderc_exe.root_module.addImport("clap", clap.module("clap"));

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
