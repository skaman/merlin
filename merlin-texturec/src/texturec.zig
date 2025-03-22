const std = @import("std");

const image = @import("merlin_image");
const ktx = @import("merlin_ktx");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Options = struct {
    compression: bool = false,
    normalmap: bool = false,
    level: u32 = 2,
    quality: u32 = 128,
    threads: ?u32 = null,
    mipmaps: bool = false,
    edge: image.ResizeEdge = .clamp,
    filter: image.ResizeFilter = .auto,
    srgb: bool = false,
};

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn convert(
    allocator: std.mem.Allocator,
    input_file: []const u8,
    options: Options,
) !ktx.Texture {
    const texture = try ktx.Texture.init(
        allocator,
        input_file,
        options.srgb,
    );
    errdefer texture.deinit();

    if (options.mipmaps) {
        try texture.genMipmaps(
            0,
            0,
            options.edge,
            options.filter,
        );
    }

    if (options.compression) {
        const threads = options.threads orelse @as(u32, @intCast(try std.Thread.getCpuCount() * 2));
        try texture.compress(
            options.normalmap,
            options.level,
            options.quality,
            threads,
        );
    }

    return texture;
}
