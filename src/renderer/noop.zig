const std = @import("std");

const z3dfx = @import("z3dfx.zig");

pub const NoopRenderer = struct {
    pub fn deinit(_: *NoopRenderer) void {}
    pub fn createShader(_: *NoopRenderer, _: z3dfx.ShaderHandle, _: []const u8) !void {}
    pub fn destroyShader(_: *NoopRenderer, _: z3dfx.ShaderHandle) void {}
    pub fn createProgram(_: *NoopRenderer, _: z3dfx.ProgramHandle, _: z3dfx.ShaderHandle, _: z3dfx.ShaderHandle) !void {}
    pub fn destroyProgram(_: *NoopRenderer, _: z3dfx.ProgramHandle) void {}
};
