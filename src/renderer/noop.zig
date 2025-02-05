const std = @import("std");

pub const NoopRenderer = struct {
    pub fn deinit(_: *NoopRenderer) void {}
};
