const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //--------------------------------------------------------------------------------------------------
    // dependencies
    //--------------------------------------------------------------------------------------------------
    const glfw = b.dependency("glfw", .{});
    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const vulkan_utility_libraries = b.dependency("vulkan_utility_libraries", .{});
    const libshaderc = b.dependency("libshaderc", .{});
    const spirv_reflect = b.dependency("spirv_reflect", .{});
    const clap = b.dependency("clap", .{});

    //--------------------------------------------------------------------------------------------------
    // shared
    //--------------------------------------------------------------------------------------------------
    const shared_lib_mod = b.createModule(.{
        .root_source_file = b.path("shared/src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const shared_lib = b.addSharedLibrary(.{
        .name = "shared",
        .root_module = shared_lib_mod,
    });
    b.installArtifact(shared_lib);

    //--------------------------------------------------------------------------------------------------
    // engine
    //--------------------------------------------------------------------------------------------------
    const engine_exe_mod = b.createModule(.{
        .root_source_file = b.path("engine/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const engine_exe = b.addExecutable(.{
        .name = "engine",
        .root_module = engine_exe_mod,
    });
    b.installArtifact(engine_exe);
    engine_exe.linkLibC();
    engine_exe.linkLibrary(glfw.artifact("glfw"));
    engine_exe.addIncludePath(b.path("vendor/glfw/upstream/include"));
    engine_exe.linkLibrary(vulkan_headers.artifact("vulkan_headers"));
    engine_exe.addIncludePath(b.path("vendor/vulkan-headers/upstream/include"));
    engine_exe.linkLibrary(vulkan_utility_libraries.artifact("vulkan_utility_libraries"));
    engine_exe.addIncludePath(b.path("vendor/vulkan-utility-libraries/upstream/include"));
    engine_exe.root_module.addImport("shared", shared_lib_mod);

    const engine_run_cmd = b.addRunArtifact(engine_exe);
    engine_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        engine_run_cmd.addArgs(args);
    }

    const run_step = b.step("run_engine", "Run the engine");
    run_step.dependOn(&engine_run_cmd.step);

    //--------------------------------------------------------------------------------------------------
    // shaderc
    //--------------------------------------------------------------------------------------------------
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
    shaderc_exe.linkLibrary(libshaderc.artifact("libshaderc"));
    shaderc_exe.addIncludePath(b.path("vendor/shaderc/upstream/libshaderc/include"));
    shaderc_exe.linkLibrary(spirv_reflect.artifact("spirv_reflect"));
    shaderc_exe.addIncludePath(b.path("vendor/spirv-reflect/upstream"));
    shaderc_exe.root_module.addImport("clap", clap.module("clap"));
    shaderc_exe.root_module.addImport("shared", shared_lib_mod);

    const shaderc_run_cmd = b.addRunArtifact(shaderc_exe);
    shaderc_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        shaderc_run_cmd.addArgs(args);
    }

    const shaderc_run_step = b.step("run_shaderc", "Run shaderc");
    shaderc_run_step.dependOn(&shaderc_run_cmd.step);

    //--------------------------------------------------------------------------------------------------
    // geometryc
    //--------------------------------------------------------------------------------------------------
    const geometryc_exe_mod = b.createModule(.{
        .root_source_file = b.path("geometryc/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const geometryc_exe = b.addExecutable(.{
        .name = "geometryc",
        .root_module = geometryc_exe_mod,
    });
    b.installArtifact(geometryc_exe);
    geometryc_exe.linkLibC();
    geometryc_exe.root_module.addImport("clap", clap.module("clap"));
    geometryc_exe.linkLibrary(shared_lib);

    const geometryc_run_cmd = b.addRunArtifact(geometryc_exe);
    geometryc_run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        geometryc_run_cmd.addArgs(args);
    }

    const geometryc_run_step = b.step("run_geometryc", "Run geometryc");
    geometryc_run_step.dependOn(&geometryc_run_cmd.step);

    //--------------------------------------------------------------------------------------------------
    // checks
    //--------------------------------------------------------------------------------------------------
    const check = b.step("check", "Check if the projects compiles");
    check.dependOn(&engine_exe.step);
    check.dependOn(&shaderc_exe.step);
    check.dependOn(&geometryc_exe.step);
}
