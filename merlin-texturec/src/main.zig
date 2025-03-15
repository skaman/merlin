const std = @import("std");

const clap = @import("clap");

const c = @import("c.zig").c;

// For some reason this method is missing from the header file
extern fn ktxTexture2_SetImageFromMemory(
    This: [*c]c.ktxTexture2,
    level: c.ktx_uint32_t,
    layer: c.ktx_uint32_t,
    faceSlice: c.ktx_uint32_t,
    src: [*c]c.ktx_uint8_t,
    srcSize: c.ktx_size_t,
) c.ktx_error_code_e;

fn checkKtxError(comptime message: []const u8, result: c.KTX_error_code) !void {
    if (result != c.VK_SUCCESS) {
        std.log.err("{s}: {s}", .{ message, c.ktxErrorString(result) });
        return error.KTXError;
    }
}

const Params = clap.parseParamsComptime(
    \\-h, --help                Display this help and exit.
    \\-c, --compression         Use Basis ETC1S compression.
    \\-n, --normalmap           Optimize compression for normal maps.
    \\-l, --level <LEVEL>       Compression level from 0 to 6. Default is 2.
    \\-q, --quality <QUALITY>   Quality level from 0 to 255. Default is 128.
    \\-t, --threads <THREADS>   Number of threads to use. Default is NUM_CPUS * 2.
    \\-m, --mipmaps             Generate image mipmaps.
    \\-e, --edge <EDGE>         Mipmaps resizing edge mode (clamp, reflect, wrap, zero). Default is clamp.
    \\-f, --filter <FILTER>     Mipmaps resizing filter mode (auto, box, triangle, cubicbspline, catmullrom, mitchell, pointsample). Default is auto.
    \\-s, --srgb                Use sRGB color space.
    \\<IN_FILE>                 Source file.
    \\<OUT_FILE>                Output file.
);

pub fn printHelp(writer: anytype) !void {
    try writer.print("Usage: merlin-texturec [options] <IN_FILE> <OUT_FILE>\n", .{});
    return clap.help(
        writer,
        clap.Help,
        &Params,
        .{ .description_on_new_line = false, .spacing_between_parameters = 0 },
    );
}

pub fn invalidArgument(writer: anytype, name: []const u8) !void {
    try writer.print("Invalid argument: {s}\n", .{name});
    try printHelp(writer);
    return error.InvalidArgument;
}

const Options = struct {
    input_file: []const u8,
    output_file: []const u8,
    compression: bool,
    normalmap: bool,
    level: u32,
    quality: u32,
    threads: u32,
    mipmaps: bool,
    edge: c.stbir_edge,
    filter: c.stbir_filter,
    srgb: bool,
};

fn parseEdgeOption(writer: anytype, value: []const u8) !c.stbir_edge {
    if (std.mem.eql(u8, value, "clamp")) {
        return c.STBIR_EDGE_CLAMP;
    } else if (std.mem.eql(u8, value, "reflect")) {
        return c.STBIR_EDGE_REFLECT;
    } else if (std.mem.eql(u8, value, "wrap")) {
        return c.STBIR_EDGE_WRAP;
    } else if (std.mem.eql(u8, value, "zero")) {
        return c.STBIR_EDGE_ZERO;
    }

    try writer.print("Invalid argument: EDGE\n", .{});
    try printHelp(writer);
    return error.InvalidArgument;
}

fn parseFilterOption(writer: anytype, value: []const u8) !c.stbir_filter {
    if (std.mem.eql(u8, value, "auto")) {
        return c.STBIR_FILTER_DEFAULT;
    } else if (std.mem.eql(u8, value, "box")) {
        return c.STBIR_FILTER_BOX;
    } else if (std.mem.eql(u8, value, "triangle")) {
        return c.STBIR_FILTER_TRIANGLE;
    } else if (std.mem.eql(u8, value, "cubicbspline")) {
        return c.STBIR_FILTER_CUBICBSPLINE;
    } else if (std.mem.eql(u8, value, "catmullrom")) {
        return c.STBIR_FILTER_CATMULLROM;
    } else if (std.mem.eql(u8, value, "mitchell")) {
        return c.STBIR_FILTER_MITCHELL;
    } else if (std.mem.eql(u8, value, "pointsample")) {
        return c.STBIR_FILTER_POINT_SAMPLE;
    }

    try writer.print("Invalid argument: FILTER\n", .{});
    try printHelp(writer);
    return error.InvalidArgument;
}

fn parseLevel(writer: anytype, value: u32) !u32 {
    if (value > 6) {
        try writer.print("Invalid argument: LEVEL\n", .{});
        try printHelp(writer);
        return error.InvalidArgument;
    }

    return value;
}

fn parseQuality(writer: anytype, value: u32) !u32 {
    if (value > 255) {
        try writer.print("Invalid argument: QUALITY\n", .{});
        try printHelp(writer);
        return error.InvalidArgument;
    }

    return value;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const std_out = std.io.getStdOut().writer();
    const std_err = std.io.getStdErr().writer();

    const parsers = comptime .{
        .FILE = clap.parsers.string,
        .IN_FILE = clap.parsers.string,
        .OUT_FILE = clap.parsers.string,
        .LEVEL = clap.parsers.int(u32, 10),
        .QUALITY = clap.parsers.int(u32, 10),
        .THREADS = clap.parsers.int(u32, 10),
        .EDGE = clap.parsers.string,
        .FILTER = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &Params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std_err, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return printHelp(std_out);
    }

    const options = Options{
        .input_file = if (res.positionals[0]) |value| value else return invalidArgument(std_err, "IN_FILE"),
        .output_file = if (res.positionals[1]) |value| value else return invalidArgument(std_err, "OUT_FILE"),
        .compression = res.args.compression != 0,
        .normalmap = res.args.normalmap != 0,
        .level = if (res.args.level) |value| try parseLevel(std_err, value) else 2,
        .quality = if (res.args.quality) |value| try parseQuality(std_err, value) else 128,
        .threads = if (res.args.threads) |value| value else @as(u32, @intCast(try std.Thread.getCpuCount() * 2)),
        .mipmaps = res.args.mipmaps != 0,
        .edge = if (res.args.edge) |value| try parseEdgeOption(std_err, value) else c.STBIR_EDGE_CLAMP,
        .filter = if (res.args.filter) |value| try parseFilterOption(std_err, value) else c.STBIR_FILTER_DEFAULT,
        .srgb = res.args.srgb != 0,
    };

    try std_out.print("Texture compiler:\n", .{});
    try std_out.print("  - Input file: {s}\n", .{options.input_file});
    try std_out.print("  - Output file: {s}\n", .{options.output_file});
    try std_out.print("  - Compression: {}\n", .{options.compression});
    try std_out.print("  - Normal map: {}\n", .{options.normalmap});
    try std_out.print("  - Compression level: {d}\n", .{options.level});
    try std_out.print("  - Compression quality: {d}\n", .{options.quality});
    try std_out.print("  - Threads: {d}\n", .{options.threads});
    try std_out.print("  - Mipmaps generation: {}\n", .{options.mipmaps});
    try std_out.print("  - Edge: {}\n", .{options.edge});
    try std_out.print("  - Filter: {}\n", .{options.filter});
    try std_out.print("  - sRGB: {}\n", .{options.srgb});

    const image = try Image.init(options.input_file);
    defer image.deinit();

    try std_out.print("Image: {d}x{d} {d} channels ({})\n", .{
        image.width,
        image.height,
        image.channels,
        image.channel_size,
    });

    const texture = try createTexture(&image, options.srgb);
    defer c.ktxTexture2_Destroy(texture);

    try checkKtxError(
        "Failed to load image data",
        ktxTexture2_SetImageFromMemory(
            texture,
            0,
            0,
            0,
            image.data.ptr,
            image.data.len,
        ),
    );

    if (options.mipmaps) {
        try std_out.print("Generating mipmaps...\n", .{});
        try genMipmaps(
            allocator,
            &image,
            0,
            0,
            &options,
            texture,
        );
    }

    if (options.compression) {
        try std_out.print("Compressing texture...\n", .{});
        var basis_params = std.mem.zeroInit(
            c.ktxBasisParams,
            .{
                .structSize = @sizeOf(c.ktxBasisParams),
                .compressionLevel = options.level,
                .qualityLevel = options.quality,
                .threadCount = options.threads,
                .normalMap = options.normalmap,
            },
        );

        try checkKtxError(
            "Failed to transcode KTX texture",
            c.ktxTexture2_CompressBasisEx(texture, &basis_params),
        );
    }

    try std_out.print("Writing KTX texture...\n", .{});
    try checkKtxError(
        "Failed to write KTX texture",
        c.ktxTexture2_WriteToNamedFile(texture, options.output_file.ptr),
    );

    try std_out.print("Done!\n", .{});
}

fn genMipmaps(
    allocator: std.mem.Allocator,
    image: *const Image,
    layer: u32,
    face_slice: u32,
    options: *const Options,
    texture: *c.ktxTexture2,
) !void {
    for (1..texture.numLevels) |level| {
        const input_data = image.data.ptr;
        const input_width = @as(u32, @intCast(image.width));
        const input_height = @as(u32, @intCast(image.height));
        const input_stride = input_width * image.channels * @as(u32, @intCast(image.channel_size.size()));

        const output_width = @as(u32, @intCast(@max(1, image.width >> @intCast(level))));
        const output_height = @as(u32, @intCast(@max(1, image.height >> @intCast(level))));
        const output_stride = output_width * image.channels * @as(u32, @intCast(image.channel_size.size()));
        const output_data = try allocator.alloc(u8, output_height * output_stride);
        defer allocator.free(output_data);

        var data_type: c.stbir_datatype = undefined;
        switch (image.channel_size) {
            .channel_u8 => {
                data_type = if (options.srgb) c.STBIR_TYPE_UINT8_SRGB else c.STBIR_TYPE_UINT8;
            },
            .channel_u16 => {
                data_type = c.STBIR_TYPE_UINT16;
            },
            .channel_f32 => {
                data_type = c.STBIR_TYPE_FLOAT;
            },
        }

        var pixel_layout: c.stbir_pixel_layout = undefined;
        if (image.channels == 1) {
            pixel_layout = c.STBIR_1CHANNEL;
        } else if (image.channels == 2) {
            pixel_layout = c.STBIR_2CHANNEL;
        } else if (image.channels == 3) {
            pixel_layout = c.STBIR_RGB;
        } else if (image.channels == 4) {
            pixel_layout = c.STBIR_RGBA;
        } else {
            std.log.err("Unsupported number of channels: {d}\n", .{image.channels});
            return error.ImageError;
        }

        _ = c.stbir_resize(
            input_data,
            @intCast(input_width),
            @intCast(input_height),
            @intCast(input_stride),
            output_data.ptr,
            @intCast(output_width),
            @intCast(output_height),
            @intCast(output_stride),
            pixel_layout,
            data_type,
            options.edge,
            options.filter,
        );

        try checkKtxError(
            "Failed to set image data",
            ktxTexture2_SetImageFromMemory(
                texture,
                @intCast(level),
                layer,
                face_slice,
                output_data.ptr,
                output_data.len,
            ),
        );
    }
}

fn createTexture(image: *const Image, srgb: bool) !*c.ktxTexture2 {
    var create_info = std.mem.zeroInit(
        c.ktxTextureCreateInfo,
        .{
            .numFaces = 1,
            .numLayers = 1,
            .isArray = false,
        },
    );

    if (image.channels == 1) {
        switch (image.channel_size) {
            .channel_u8 => {
                create_info.glInternalformat = if (srgb) c.GL_SR8_EXT else c.GL_R8;
                create_info.vkFormat = if (srgb) c.VK_FORMAT_R8_SRGB else c.VK_FORMAT_R8_UNORM;
            },
            .channel_u16 => {
                create_info.glInternalformat = c.GL_R16;
                create_info.vkFormat = c.VK_FORMAT_R16_UNORM;
            },
            .channel_f32 => {
                create_info.glInternalformat = c.GL_R32F;
                create_info.vkFormat = c.VK_FORMAT_R32_SFLOAT;
            },
        }
    } else if (image.channels == 2) {
        switch (image.channel_size) {
            .channel_u8 => {
                create_info.glInternalformat = if (srgb) c.GL_SRG8_EXT else c.GL_RG8;
                create_info.vkFormat = if (srgb) c.VK_FORMAT_R8G8_SRGB else c.VK_FORMAT_R8G8_UNORM;
            },
            .channel_u16 => {
                create_info.glInternalformat = c.GL_RG16;
                create_info.vkFormat = c.VK_FORMAT_R16G16_UNORM;
            },
            .channel_f32 => {
                create_info.glInternalformat = c.GL_RG32F;
                create_info.vkFormat = c.VK_FORMAT_R32G32_SFLOAT;
            },
        }
    } else if (image.channels == 3) {
        switch (image.channel_size) {
            .channel_u8 => {
                create_info.glInternalformat = if (srgb) c.GL_SRGB8 else c.GL_RGB8;
                create_info.vkFormat = if (srgb) c.VK_FORMAT_R8G8B8_SRGB else c.VK_FORMAT_R8G8B8_UNORM;
            },
            .channel_u16 => {
                create_info.glInternalformat = c.GL_RGB16;
                create_info.vkFormat = c.VK_FORMAT_R16G16B16_UNORM;
            },
            .channel_f32 => {
                create_info.glInternalformat = c.GL_RGB32F;
                create_info.vkFormat = c.VK_FORMAT_R32G32B32_SFLOAT;
            },
        }
    } else if (image.channels == 4) {
        switch (image.channel_size) {
            .channel_u8 => {
                create_info.glInternalformat = if (srgb) c.GL_SRGB8_ALPHA8 else c.GL_RGBA8;
                create_info.vkFormat = if (srgb) c.VK_FORMAT_R8G8B8A8_SRGB else c.VK_FORMAT_R8G8B8A8_UNORM;
            },
            .channel_u16 => {
                create_info.glInternalformat = c.GL_RGBA16;
                create_info.vkFormat = c.VK_FORMAT_R16G16B16A16_UNORM;
            },
            .channel_f32 => {
                create_info.glInternalformat = c.GL_RGBA32F;
                create_info.vkFormat = c.VK_FORMAT_R32G32B32A32_SFLOAT;
            },
        }
    } else {
        std.log.err("Unsupported number of channels: {d}\n", .{image.channels});
        return error.ImageError;
    }

    create_info.baseWidth = @intCast(image.width);
    create_info.baseHeight = @intCast(image.height);
    create_info.baseDepth = 1;
    create_info.numDimensions = 2;

    create_info.generateMipmaps = false;
    //create_info.numLevels = 1;
    const max_dim = @max(image.width, image.height);
    create_info.numLevels = @intCast(std.math.log2(max_dim) + 1);

    var ktx_texture: *c.ktxTexture2 = undefined;
    try checkKtxError(
        "Failed to create KTX texture",
        c.ktxTexture2_Create(
            &create_info,
            c.KTX_TEXTURE_CREATE_ALLOC_STORAGE,
            @ptrCast(&ktx_texture),
        ),
    );

    return ktx_texture;
}

const Image = struct {
    const Self = @This();

    pub const ChannelSize = enum {
        channel_u8,
        channel_u16,
        channel_f32,

        pub fn size(self: ChannelSize) usize {
            switch (self) {
                .channel_u8 => return 1,
                .channel_u16 => return 2,
                .channel_f32 => return 4,
            }
        }
    };

    width: usize,
    height: usize,
    channels: usize,
    channel_size: ChannelSize,
    data: []u8,

    pub fn init(path: []const u8) !Self {
        var width: c_int = 0;
        var height: c_int = 0;
        var channels: c_int = 0;
        var channel_size: ChannelSize = .channel_u8;
        var data: [*c]u8 = null;

        c.stbi_set_flip_vertically_on_load(1);

        if (c.stbi_is_hdr(path.ptr) == 1) {
            data = c.stbi_load(
                path.ptr,
                &width,
                &height,
                &channels,
                0,
            );
            channel_size = .channel_f32;
        } else if (c.stbi_is_16_bit(path.ptr) == 1) {
            data = @ptrCast(c.stbi_load_16(
                path.ptr,
                &width,
                &height,
                &channels,
                0,
            ));
            channel_size = .channel_u16;
        } else {
            data = c.stbi_load(
                path.ptr,
                &width,
                &height,
                &channels,
                0,
            );
            channel_size = .channel_u8;
        }

        if (data == null) {
            std.log.err("Failed to load image: {s}\n", .{path});
            return error.ImageError;
        }

        const size = @as(
            usize,
            @intCast(width * height * channels * @as(c_int, @intCast(channel_size.size()))),
        );

        return Image{
            .width = @intCast(width),
            .height = @intCast(height),
            .channels = @intCast(channels),
            .channel_size = channel_size,
            .data = data[0..size],
        };
    }

    pub fn deinit(self: *const Self) void {
        c.stbi_image_free(self.data.ptr);
    }
};
