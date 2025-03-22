const std = @import("std");

const c = @import("c.zig").c;

pub const ResizeEdge = enum(u8) {
    clamp = c.STBIR_EDGE_CLAMP,
    reflect = c.STBIR_EDGE_REFLECT,
    wrap = c.STBIR_EDGE_WRAP,
    zero = c.STBIR_EDGE_ZERO,
};

pub const ResizeFilter = enum(u8) {
    auto = c.STBIR_FILTER_DEFAULT,
    box = c.STBIR_FILTER_BOX,
    triangle = c.STBIR_FILTER_TRIANGLE,
    cubic_spline = c.STBIR_FILTER_CUBICBSPLINE,
    catmull_rom = c.STBIR_FILTER_CATMULLROM,
    mitchell = c.STBIR_FILTER_MITCHELL,
    point_sample = c.STBIR_FILTER_POINT_SAMPLE,
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

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Image {
        var width: c_int = 0;
        var height: c_int = 0;
        var channels: c_int = 0;
        var channel_size: ChannelSize = .u8;
        var image: [*c]u8 = null;

        c.stbi_set_flip_vertically_on_load(1);

        if (c.stbi_is_hdr(path.ptr) == 1) {
            image = c.stbi_load(
                path.ptr,
                &width,
                &height,
                &channels,
                0,
            );
            channel_size = .f32;
        } else if (c.stbi_is_16_bit(path.ptr) == 1) {
            image = @ptrCast(c.stbi_load_16(
                path.ptr,
                &width,
                &height,
                &channels,
                0,
            ));
            channel_size = .u16;
        } else {
            image = c.stbi_load(
                path.ptr,
                &width,
                &height,
                &channels,
                0,
            );
            channel_size = .u8;
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
            .srgb = true,
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
    ) Image {
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

        const resized_image = Image.init(
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
            self.image.ptr,
            @intCast(self.width),
            @intCast(self.height),
            @intCast(input_stride),
            resized_image.ptr,
            @intCast(width),
            @intCast(height),
            @intCast(output_stride),
            @intFromEnum(pixel_layout),
            @intFromEnum(data_type),
            @intFromEnum(edge),
            @intFromEnum(filter),
        );

        return resized_image;
    }
};
