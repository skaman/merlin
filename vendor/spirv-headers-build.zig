const std = @import("std");

pub fn linkLibrary(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
) void {
    exe.addIncludePath(b.path("vendor/spirv-headers/include"));
    exe.addIncludePath(b.path("vendor/spirv-headers/include/spirv/unified1/"));
}
