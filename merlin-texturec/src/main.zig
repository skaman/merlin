const std = @import("std");

const clap = @import("clap");
const image = @import("merlin_image");
const texturec = @import("texturec");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Options = struct {
    input_file: []const u8,
    output_file: []const u8,
    conversion_options: texturec.Options,
};

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

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn printHelp(writer: anytype) !void {
    try writer.print("Usage: merlin-texturec [options] <IN_FILE> <OUT_FILE>\n", .{});
    return clap.help(
        writer,
        clap.Help,
        &Params,
        .{ .description_on_new_line = false, .spacing_between_parameters = 0 },
    );
}

fn invalidArgument(writer: anytype, name: []const u8) !void {
    try writer.print("Invalid argument: {s}\n", .{name});
    try printHelp(writer);
    return error.InvalidArgument;
}

fn parseEdgeOption(writer: anytype, value: []const u8) !image.ResizeEdge {
    if (std.mem.eql(u8, value, "clamp")) {
        return .clamp;
    } else if (std.mem.eql(u8, value, "reflect")) {
        return .reflect;
    } else if (std.mem.eql(u8, value, "wrap")) {
        return .wrap;
    } else if (std.mem.eql(u8, value, "zero")) {
        return .zero;
    }

    try writer.print("Invalid argument: EDGE\n", .{});
    try printHelp(writer);
    return error.InvalidArgument;
}

fn parseFilterOption(writer: anytype, value: []const u8) !image.ResizeFilter {
    if (std.mem.eql(u8, value, "auto")) {
        return .auto;
    } else if (std.mem.eql(u8, value, "box")) {
        return .box;
    } else if (std.mem.eql(u8, value, "triangle")) {
        return .triangle;
    } else if (std.mem.eql(u8, value, "cubicbspline")) {
        return .cubic_spline;
    } else if (std.mem.eql(u8, value, "catmullrom")) {
        return .catmull_rom;
    } else if (std.mem.eql(u8, value, "mitchell")) {
        return .mitchell;
    } else if (std.mem.eql(u8, value, "pointsample")) {
        return .point_sample;
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

// *********************************************************************************************
// Main
// *********************************************************************************************

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

    var options = Options{
        .input_file = if (res.positionals[0]) |value| value else return invalidArgument(std_err, "IN_FILE"),
        .output_file = if (res.positionals[1]) |value| value else return invalidArgument(std_err, "OUT_FILE"),
        .conversion_options = .{},
    };

    if (res.args.compression != 0) {
        options.conversion_options.compression = true;
    }
    if (res.args.normalmap != 0) {
        options.conversion_options.normalmap = true;
    }
    if (res.args.level) |value| {
        options.conversion_options.level = try parseLevel(std_err, value);
    }
    if (res.args.quality) |value| {
        options.conversion_options.quality = try parseQuality(std_err, value);
    }
    if (res.args.threads) |value| {
        options.conversion_options.threads = value;
    }
    if (res.args.mipmaps != 0) {
        options.conversion_options.mipmaps = true;
    }
    if (res.args.edge) |value| {
        options.conversion_options.edge = try parseEdgeOption(std_err, value);
    }
    if (res.args.filter) |value| {
        options.conversion_options.filter = try parseFilterOption(std_err, value);
    }
    if (res.args.srgb != 0) {
        options.conversion_options.srgb = true;
    }

    try std_out.print("Texture compiler:\n", .{});
    try std_out.print("  - Input file: {s}\n", .{options.input_file});
    try std_out.print("  - Output file: {s}\n", .{options.output_file});
    try std_out.print("  - Compression: {}\n", .{options.conversion_options.compression});
    try std_out.print("  - Normal map: {}\n", .{options.conversion_options.normalmap});
    try std_out.print("  - Compression level: {d}\n", .{options.conversion_options.level});
    try std_out.print("  - Compression quality: {d}\n", .{options.conversion_options.quality});
    try std_out.print("  - Threads: {d}\n", .{if (options.conversion_options.threads) |value| value else 0});
    try std_out.print("  - Mipmaps generation: {}\n", .{options.conversion_options.mipmaps});
    try std_out.print("  - Edge: {s}\n", .{options.conversion_options.edge.name()});
    try std_out.print("  - Filter: {s}\n", .{options.conversion_options.filter.name()});
    try std_out.print("  - sRGB: {}\n", .{options.conversion_options.srgb});

    const texture = try texturec.convert(
        allocator,
        options.input_file,
        options.conversion_options,
    );
    defer texture.deinit();

    try std_out.print("Image: {d}x{d} {d} channels ({s})\n", .{
        texture.image.width,
        texture.image.height,
        texture.image.channels,
        texture.image.channel_size.name(),
    });

    try texture.save(options.output_file);

    try std_out.print("Done!\n", .{});
}
