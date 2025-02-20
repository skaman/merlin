const std = @import("std");

const spirv_headers_build = @import("spirv-headers-build.zig");
const spirv_tools_build = @import("spirv-tools-build.zig");

pub fn addLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    spirv_tools: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const glslang = b.addStaticLibrary(.{
        .name = "glslang",
        .target = target,
        .optimize = optimize,
    });

    //const tag = target.result.os.tag;
    //if (tag == .windows) {
    //    spirv_tools.root_module.addCMacro("SPIRV_WINDOWS", "");
    //} else if (tag == .linux) {
    //    spirv_tools.root_module.addCMacro("SPIRV_LINUX", "");
    //} else if (tag == .macos) {
    //    spirv_tools.root_module.addCMacro("SPIRV_MAC", "");
    //} else if (tag == .ios) {
    //    spirv_tools.root_module.addCMacro("SPIRV_IOS", "");
    //} else if (tag == .tvos) {
    //    spirv_tools.root_module.addCMacro("SPIRV_TVOS", "");
    //} else if (tag == .freebsd) {
    //    spirv_tools.root_module.addCMacro("SPIRV_FREEBSD", "");
    //} else if (tag == .openbsd) {
    //    spirv_tools.root_module.addCMacro("SPIRV_OPENBSD", "");
    //} else if (tag == .fuchsia) {
    //    spirv_tools.root_module.addCMacro("SPIRV_FUCHSIA", "");
    //} else {
    //    std.log.err("Incompatible target platform.", .{});
    //    std.process.exit(1);
    //}

    glslang.linkLibCpp();
    //spirv_tools.addIncludePath(b.path("vendor/spirv-tools"));
    //spirv_tools.addIncludePath(b.path("vendor/spirv-tools/include"));
    //spirv_tools.addIncludePath(b.path("vendor/spirv-tools-generated"));

    const src_dir = "vendor/glslang/";
    glslang.addCSourceFiles(.{
        .files = &.{
            // glslang - GenericCodeGen
            src_dir ++ "GenericCodeGen/CodeGen.cpp",
            src_dir ++ "GenericCodeGen/Link.cpp",
            // glslang - ResourceLimits
            src_dir ++ "ResourceLimits/resource_limits_c.cpp",
            src_dir ++ "ResourceLimits/ResourceLimits.cpp",
            // glslang - MachineIndependent
            src_dir ++ "MachineIndependent/attribute.cpp",
            src_dir ++ "MachineIndependent/Constant.cpp",
            src_dir ++ "MachineIndependent/glslang_tab.cpp",
            src_dir ++ "MachineIndependent/InfoSink.cpp",
            src_dir ++ "MachineIndependent/Initialize.cpp",
            src_dir ++ "MachineIndependent/Intermediate.cpp",
            src_dir ++ "MachineIndependent/intermOut.cpp",
            src_dir ++ "MachineIndependent/IntermTraverse.cpp",
            src_dir ++ "MachineIndependent/iomapper.cpp",
            src_dir ++ "MachineIndependent/limits.cpp",
            src_dir ++ "MachineIndependent/linkValidate.cpp",
            src_dir ++ "MachineIndependent/parseConst.cpp",
            src_dir ++ "MachineIndependent/ParseContextBase.cpp",
            src_dir ++ "MachineIndependent/ParseHelper.cpp",
            src_dir ++ "MachineIndependent/PoolAlloc.cpp",
            src_dir ++ "MachineIndependent/preprocessor/Pp.cpp",
            src_dir ++ "MachineIndependent/preprocessor/PpAtom.cpp",
            src_dir ++ "MachineIndependent/preprocessor/PpContext.cpp",
            src_dir ++ "MachineIndependent/preprocessor/PpScanner.cpp",
            src_dir ++ "MachineIndependent/preprocessor/PpTokens.cpp",
            src_dir ++ "MachineIndependent/propagateNoContraction.cpp",
            src_dir ++ "MachineIndependent/reflection.cpp",
            src_dir ++ "MachineIndependent/RemoveTree.cpp",
            src_dir ++ "MachineIndependent/Scan.cpp",
            src_dir ++ "MachineIndependent/ShaderLang.cpp",
            src_dir ++ "MachineIndependent/SpirvIntrinsics.cpp",
            src_dir ++ "MachineIndependent/SymbolTable.cpp",
            src_dir ++ "MachineIndependent/Versions.cpp",
            // glslang - OSDependent
            if (target.result.os.tag == .windows)
                "glslang/OSDependent/Windows/ossource.cpp"
            else
                "glslang/OSDependent/Unix/ossource.cpp",
            // glslang
            src_dir ++ "glslang/CInterface/glslang_c_interface.cpp",
            // SPIRV
            src_dir ++ "SPIRV/CInterface/spirv_c_interface.cpp",
            src_dir ++ "SPIRV/disassemble.cpp",
            src_dir ++ "SPIRV/doc.cpp",
            src_dir ++ "SPIRV/GlslangToSpv.cpp",
            src_dir ++ "SPIRV/InReadableOrder.cpp",
            src_dir ++ "SPIRV/Logger.cpp",
            src_dir ++ "SPIRV/SpvBuilder.cpp",
            src_dir ++ "SPIRV/SpvPostProcess.cpp",
            src_dir ++ "SPIRV/SpvTools.cpp",
            src_dir ++ "SPIRV/SPVRemapper.cpp",
            // StandAlone
            src_dir ++ "StandAlone/StandAlone.cpp",
            src_dir ++ "StandAlone/spirv-remap.cpp",
        },
        //.flags = &.{"-D_GLFW_WIN32"},
    });

    spirv_headers_build.linkLibrary(b, glslang);
    spirv_tools_build.linkLibrary(b, glslang, spirv_tools);

    return spirv_tools;
}

pub fn linkLibrary(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    spirv_tools: *std.Build.Step.Compile,
) void {
    exe.linkLibrary(spirv_tools);
    exe.addIncludePath(b.path("vendor/spirv-tools/include/"));
}
