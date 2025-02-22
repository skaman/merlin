const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("glslang", .{});

    const lib = b.addStaticLibrary(.{
        .name = "glslang",
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibCpp();
    lib.addIncludePath(b.path("upstream/"));
    lib.addIncludePath(b.path("generated/"));

    const src_dir = "upstream/";
    lib.addCSourceFiles(.{
        .files = &.{
            // glslang - GenericCodeGen
            src_dir ++ "glslang/GenericCodeGen/CodeGen.cpp",
            src_dir ++ "glslang/GenericCodeGen/Link.cpp",
            // glslang - ResourceLimits
            src_dir ++ "glslang/ResourceLimits/resource_limits_c.cpp",
            src_dir ++ "glslang/ResourceLimits/ResourceLimits.cpp",
            // glslang - MachineIndependent
            src_dir ++ "glslang/MachineIndependent/attribute.cpp",
            src_dir ++ "glslang/MachineIndependent/Constant.cpp",
            src_dir ++ "glslang/MachineIndependent/glslang_tab.cpp",
            src_dir ++ "glslang/MachineIndependent/InfoSink.cpp",
            src_dir ++ "glslang/MachineIndependent/Initialize.cpp",
            src_dir ++ "glslang/MachineIndependent/Intermediate.cpp",
            src_dir ++ "glslang/MachineIndependent/intermOut.cpp",
            src_dir ++ "glslang/MachineIndependent/IntermTraverse.cpp",
            src_dir ++ "glslang/MachineIndependent/iomapper.cpp",
            src_dir ++ "glslang/MachineIndependent/limits.cpp",
            src_dir ++ "glslang/MachineIndependent/linkValidate.cpp",
            src_dir ++ "glslang/MachineIndependent/parseConst.cpp",
            src_dir ++ "glslang/MachineIndependent/ParseContextBase.cpp",
            src_dir ++ "glslang/MachineIndependent/ParseHelper.cpp",
            src_dir ++ "glslang/MachineIndependent/PoolAlloc.cpp",
            src_dir ++ "glslang/MachineIndependent/preprocessor/Pp.cpp",
            src_dir ++ "glslang/MachineIndependent/preprocessor/PpAtom.cpp",
            src_dir ++ "glslang/MachineIndependent/preprocessor/PpContext.cpp",
            src_dir ++ "glslang/MachineIndependent/preprocessor/PpScanner.cpp",
            src_dir ++ "glslang/MachineIndependent/preprocessor/PpTokens.cpp",
            src_dir ++ "glslang/MachineIndependent/propagateNoContraction.cpp",
            src_dir ++ "glslang/MachineIndependent/reflection.cpp",
            src_dir ++ "glslang/MachineIndependent/RemoveTree.cpp",
            src_dir ++ "glslang/MachineIndependent/Scan.cpp",
            src_dir ++ "glslang/MachineIndependent/ShaderLang.cpp",
            src_dir ++ "glslang/MachineIndependent/SpirvIntrinsics.cpp",
            src_dir ++ "glslang/MachineIndependent/SymbolTable.cpp",
            src_dir ++ "glslang/MachineIndependent/Versions.cpp",
            // glslang - OSDependent
            if (target.result.os.tag == .windows)
                src_dir ++ "glslang/OSDependent/Windows/ossource.cpp"
            else
                src_dir ++ "glslang/OSDependent/Unix/ossource.cpp",
            // glslang - HLSL
            src_dir ++ "glslang/HLSL/hlslAttributes.cpp",
            src_dir ++ "glslang/HLSL/hlslGrammar.cpp",
            src_dir ++ "glslang/HLSL/hlslOpMap.cpp",
            src_dir ++ "glslang/HLSL/hlslParseables.cpp",
            src_dir ++ "glslang/HLSL/hlslParseHelper.cpp",
            src_dir ++ "glslang/HLSL/hlslScanContext.cpp",
            src_dir ++ "glslang/HLSL/hlslTokenStream.cpp",
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
        },
        .flags = &.{ "-DENABLE_OPT=true", "-DENABLE_SPIRV=true", "-DENABLE_HLSL=1" },
    });

    const spirv_headers = b.dependency("spirv_headers", .{});
    lib.linkLibrary(spirv_headers.artifact("spirv_headers"));

    const spirv_tools = b.dependency("spirv_tools", .{});
    lib.linkLibrary(spirv_tools.artifact("spirv_tools"));

    b.installArtifact(lib);
}
