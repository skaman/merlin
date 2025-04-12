const std = @import("std");

const c = @import("c.zig").c;

// *********************************************************************************************
// Enums
// *********************************************************************************************

pub const ResizeEdge = enum(u8) {
    clamp = c.STBIR_EDGE_CLAMP,
    reflect = c.STBIR_EDGE_REFLECT,
    wrap = c.STBIR_EDGE_WRAP,
    zero = c.STBIR_EDGE_ZERO,

    pub fn name(self: ResizeEdge) []const u8 {
        switch (self) {
            .clamp => return "clamp",
            .reflect => return "reflect",
            .wrap => return "wrap",
            .zero => return "zero",
        }
    }
};

pub const ResizeFilter = enum(u8) {
    auto = c.STBIR_FILTER_DEFAULT,
    box = c.STBIR_FILTER_BOX,
    triangle = c.STBIR_FILTER_TRIANGLE,
    cubic_spline = c.STBIR_FILTER_CUBICBSPLINE,
    catmull_rom = c.STBIR_FILTER_CATMULLROM,
    mitchell = c.STBIR_FILTER_MITCHELL,
    point_sample = c.STBIR_FILTER_POINT_SAMPLE,

    pub fn name(self: ResizeFilter) []const u8 {
        switch (self) {
            .auto => return "auto",
            .box => return "box",
            .triangle => return "triangle",
            .cubic_spline => return "cubic_spline",
            .catmull_rom => return "catmull_rom",
            .mitchell => return "mitchell",
            .point_sample => return "point_sample",
        }
    }
};

pub const ChannelSize = enum {
    u8,
    u16,
    f32,

    pub fn size(self: ChannelSize) usize {
        switch (self) {
            .u8 => return 1,
            .u16 => return 2,
            .f32 => return 4,
        }
    }

    pub fn name(self: ChannelSize) []const u8 {
        switch (self) {
            .u8 => return "u8",
            .u16 => return "u16",
            .f32 => return "f32",
        }
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn checkPngSrgb(file: std.fs.File) !bool {
    try file.seekTo(8);

    while (true) {
        const length = try file.reader().readInt(u32, .big);
        var chunk_type: [4]u8 = undefined;
        if (try file.readAll(&chunk_type) != chunk_type.len) {
            return error.ImageError;
        }
        if (!std.mem.eql(u8, &chunk_type, "sRGB")) {
            return true;
        }
        if (!std.mem.eql(u8, &chunk_type, "IEND")) {
            break;
        }
        try file.seekBy(length + 4);
    }

    return false;
}

fn checkJpegSrgb(file: std.fs.File) !bool {
    try file.seekTo(2);

    while (true) {
        const sc = try file.reader().readByte();
        if (sc != 0xff) {
            continue;
        }

        const marker = try file.reader().readByte();
        if (marker == 0xe2) {
            var seq_length = try file.reader().readInt(u16, .big);

            var identifier: [11]u8 = undefined;
            if (seq_length >= 11) {
                if (try file.readAll(&identifier) != identifier.len) {
                    return error.ImageError;
                }
                seq_length -= 11;

                if (std.mem.eql(u8, &identifier, "ICC_PROFILE")) {
                    var buffer: [128]u8 = undefined;
                    const to_read = if (seq_length < buffer.len - 1) seq_length else buffer.len - 1;
                    if (try file.readAll(buffer[0..to_read]) != to_read) {
                        return error.ImageError;
                    }

                    if (std.mem.indexOf(u8, &buffer, "sRGB") != null) {
                        return true;
                    } else {
                        return false;
                    }
                } else {
                    try file.seekBy(seq_length);
                }
            } else {
                try file.seekBy(seq_length);
            }
        } else if (marker >= 0xd0 and marker <= 0xd9) {
            continue;
        } else {
            const seq_length = try file.reader().readInt(u16, .big);
            if (seq_length < 2) {
                return error.ImageError;
            }
            try file.seekBy(seq_length - 2);
        }
    }

    return true;
}

fn checkTiffSrgb(file: std.fs.File) !bool {
    try file.seekTo(0);

    var header: [2]u8 = undefined;
    if (try file.readAll(&header) != header.len) {
        return error.ImageError;
    }

    var endianess: std.builtin.Endian = undefined;
    if (header[0] == 'I' and header[1] == 'I') {
        endianess = .little;
    } else if (header[0] == 'M' and header[1] == 'M') {
        endianess = .big;
    } else {
        return false;
    }

    const magic = try file.reader().readInt(u16, endianess);
    if (magic != 42) {
        return false;
    }

    const ifd_offset = try file.reader().readInt(u32, endianess);
    try file.seekTo(ifd_offset);

    const num_entries = try file.reader().readInt(u16, endianess);
    for (0..num_entries) |_| {
        const tag = try file.reader().readInt(u16, endianess);
        if (tag == 34675) {
            return true;
        }

        try file.seekBy(10);
    }

    return true;
}

fn isImageSrgb(path: []const u8) !bool {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var header: [8]u8 = undefined;
    if (try file.readAll(&header) != header.len) {
        return error.ImageError;
    }

    // check for PNG
    if (std.mem.eql(u8, &header, "\x89PNG\r\n\x1a\n")) {
        return try checkPngSrgb(file);
    }
    // check for JPEG
    if (header[0] == 0xff and header[1] == 0xd8) {
        return try checkJpegSrgb(file);
    }
    // check for TIFF
    if ((header[0] == 'I' and header[1] == 'I' and header[2] == 42 and header[3] == 0) or
        (header[0] == 'M' and header[1] == 'M' and header[2] == 0 and header[3] == 42))
    {
        return try checkTiffSrgb(file);
    }

    return false;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub const Image = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    channels: usize,
    channel_size: ChannelSize,
    srgb: bool,
    data: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
        channels: usize,
        channel_size: ChannelSize,
        srgb: bool,
    ) !Image {
        const size = width * height * channels * channel_size.size();
        const data = try allocator.alloc(u8, size);

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .channels = channels,
            .channel_size = channel_size,
            .srgb = srgb,
            .data = data,
        };
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8, desired_channels: u8) !Image {
        var width: c_int = 0;
        var height: c_int = 0;
        var channels: c_int = 0;
        var channel_size: ChannelSize = .u8;
        var image: [*c]u8 = null;

        const srgb = try isImageSrgb(path);

        c.stbi_set_flip_vertically_on_load(1);

        if (c.stbi_is_hdr(path.ptr) == 1) {
            image = @ptrCast(c.stbi_loadf(
                path.ptr,
                &width,
                &height,
                &channels,
                desired_channels,
            ));
            channel_size = .f32;
        } else if (c.stbi_is_16_bit(path.ptr) == 1) {
            image = @ptrCast(c.stbi_load_16(
                path.ptr,
                &width,
                &height,
                &channels,
                desired_channels,
            ));
            channel_size = .u16;
        } else {
            image = c.stbi_load(
                path.ptr,
                &width,
                &height,
                &channels,
                desired_channels,
            );
            channel_size = .u8;
        }

        if (desired_channels != 0) {
            channels = @intCast(desired_channels);
        }

        if (image == null) {
            std.log.err("Failed to load image: {s}\n", .{path});
            return error.ImageError;
        }
        defer c.stbi_image_free(image);

        const size = @as(
            usize,
            @intCast(width * height * channels * @as(c_int, @intCast(channel_size.size()))),
        );

        // TODO: is it possible to load directly in our buffer? stb_image limitation?
        const data = try allocator.alloc(u8, size);
        @memcpy(data, image[0..size]);

        return .{
            .allocator = allocator,
            .width = @intCast(width),
            .height = @intCast(height),
            .channels = @intCast(channels),
            .channel_size = channel_size,
            .srgb = srgb,
            .data = data,
        };
    }

    pub fn deinit(self: *const Image) void {
        self.allocator.free(self.data);
    }

    pub fn resize(
        self: *const Image,
        width: usize,
        height: usize,
        edge: ResizeEdge,
        filter: ResizeFilter,
    ) !Image {
        const data_type: c.stbir_datatype =
            switch (self.channel_size) {
                .u8 => if (self.srgb) c.STBIR_TYPE_UINT8_SRGB else c.STBIR_TYPE_UINT8,
                .u16 => c.STBIR_TYPE_UINT16,
                .f32 => c.STBIR_TYPE_FLOAT,
            };

        const pixel_layout: c.stbir_pixel_layout =
            switch (self.channels) {
                1 => c.STBIR_1CHANNEL,
                2 => c.STBIR_2CHANNEL,
                3 => c.STBIR_RGB,
                4 => c.STBIR_RGBA,
                else => {
                    std.log.err("Unsupported number of channels: {d}\n", .{self.channels});
                    return error.ImageError;
                },
            };

        const resized_image = try Image.init(
            self.allocator,
            width,
            height,
            self.channels,
            self.channel_size,
            self.srgb,
        );
        errdefer resized_image.deinit();

        const input_stride = self.width * self.channels * self.channel_size.size();
        const output_stride = width * self.channels * self.channel_size.size();

        _ = c.stbir_resize(
            self.data.ptr,
            @intCast(self.width),
            @intCast(self.height),
            @intCast(input_stride),
            resized_image.data.ptr,
            @intCast(width),
            @intCast(height),
            @intCast(output_stride),
            pixel_layout,
            data_type,
            @intFromEnum(edge),
            @intFromEnum(filter),
        );

        return resized_image;
    }
};
