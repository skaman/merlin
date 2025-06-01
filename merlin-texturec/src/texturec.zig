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
};

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn convert(
    allocator: std.mem.Allocator,
    input_file: []const u8,
    options: Options,
) !ktx.Texture {
    const source = try image.Image.load(
        allocator,
        input_file,
        0,
    );

    const max_dim = @max(source.width, source.height);
    const num_levels = if (options.mipmaps) std.math.log2(max_dim) + 1 else 1;
    const texture = try ktx.Texture.init(
        allocator,
        .{
            .num_channels = source.channels,
            .channel_size = source.channel_size,
            .srgb = source.srgb,
            .base_width = @intCast(source.width),
            .base_height = @intCast(source.height),
            .num_levels = @intCast(num_levels),
        },
    );
    errdefer texture.deinit();

    try texture.setImage(
        source.data,
        0,
        0,
        0,
    );

    if (options.mipmaps) {
        for (1..num_levels) |level| {
            const output_width = @as(u32, @intCast(@max(1, source.width >> @intCast(level))));
            const output_height = @as(u32, @intCast(@max(1, source.height >> @intCast(level))));

            const resized_image = try source.resize(
                output_width,
                output_height,
                options.edge,
                options.filter,
            );
            defer resized_image.deinit();

            try texture.setImage(
                resized_image.data,
                @intCast(level),
                0,
                0,
            );
        }
    }

    if (options.compression) {
        const threads = options.threads orelse @as(u32, @intCast(try std.Thread.getCpuCount() * 2));
        try texture.compressBasis(
            options.normalmap,
            options.level,
            options.quality,
            threads,
        );
    }

    return texture;
}
