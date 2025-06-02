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
    cubemap: bool = false,
};

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn convert(
    allocator: std.mem.Allocator,
    input_files: []const []const u8,
    options: Options,
) !ktx.Texture {
    if (options.cubemap) {
        if (input_files.len != 6) {
            return error.InvalidArgument;
        }
    } else if (input_files.len == 0) {
        return error.InvalidArgument;
    }

    var texture: ?ktx.Texture = null;
    errdefer if (texture != null) texture.?.deinit();
    var num_channels: usize = undefined;
    var channel_size: image.ChannelSize = undefined;
    var srgb: bool = undefined;
    var base_width: u32 = undefined;
    var base_height: u32 = undefined;

    var layer_index: u32 = 0;
    var face_index: u32 = 0;
    for (input_files) |input_file| {
        const source = try image.Image.load(
            allocator,
            input_file,
            0,
        );
        defer source.deinit();

        const max_dim = @max(source.width, source.height);
        const num_levels = if (options.mipmaps) std.math.log2(max_dim) + 1 else 1;
        if (texture == null) {
            num_channels = source.channels;
            channel_size = source.channel_size;
            srgb = source.srgb;
            base_width = @intCast(source.width);
            base_height = @intCast(source.height);
            texture = try ktx.Texture.init(
                allocator,
                .{
                    .num_channels = num_channels,
                    .channel_size = channel_size,
                    .srgb = srgb,
                    .base_width = @intCast(base_width),
                    .base_height = @intCast(base_height),
                    .num_levels = @intCast(num_levels),
                    .num_layers = @intCast(if (options.cubemap) 1 else input_files.len),
                    .num_faces = if (options.cubemap) 6 else 1,
                },
            );
        } else {
            if (source.channels != num_channels) {
                return error.ChannelMismatch;
            }
            if (source.channel_size != channel_size) {
                return error.ChannelSizeMismatch;
            }
            if (source.srgb != srgb) {
                return error.SrgbMismatch;
            }
            if (source.width != base_width or source.height != base_height) {
                return error.DimensionMismatch;
            }
        }

        try texture.?.setImage(
            source.data,
            0,
            layer_index,
            face_index,
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

                try texture.?.setImage(
                    resized_image.data,
                    @intCast(level),
                    layer_index,
                    face_index,
                );
            }
        }

        if (options.cubemap) face_index += 1 else layer_index += 1;
    }

    if (options.compression) {
        const threads = options.threads orelse @as(u32, @intCast(try std.Thread.getCpuCount() * 2));
        try texture.?.compressBasis(
            options.normalmap,
            options.level,
            options.quality,
            threads,
        );
    }

    return texture.?;
}
