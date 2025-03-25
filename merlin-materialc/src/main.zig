const std = @import("std");

const clap = @import("clap");
const gltf = @import("merlin_gltf");
const image = @import("merlin_image");
const materialc = @import("materialc");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Options = struct {
    input_file: []const u8,
    output_dir: []const u8,
    conversion_options: materialc.Options,
};

const Params = clap.parseParamsComptime(
    \\-h, --help                Display this help and exit.
    \\-c, --compression         Use Basis ETC1S compression.
    \\-l, --level <LEVEL>       Compression level from 0 to 6. Default is 2.
    \\-q, --quality <QUALITY>   Quality level from 0 to 255. Default is 128.
    \\-t, --threads <THREADS>   Number of threads to use. Default is NUM_CPUS * 2.
    \\-m, --mipmaps             Generate image mipmaps.
    \\-e, --edge <EDGE>         Mipmaps resizing edge mode (clamp, reflect, wrap, zero). Default is clamp.
    \\-f, --filter <FILTER>     Mipmaps resizing filter mode (auto, box, triangle, cubicbspline, catmullrom, mitchell, pointsample). Default is auto.
    \\<IN_FILE>                 Source file.
    \\<OUT_FILE>                Output file.
);

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn printHelp(writer: anytype) !void {
    try writer.print("Usage: merlin-materialc [options] <IN_FILE> <OUT_FILE>\n", .{});
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

fn getOutputFileName(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    filename: []const u8,
) ![]const u8 {
    return try std.fs.path.join(allocator, &[_][]const u8{ output_dir, filename });
}

fn getOutputMaterialFileName(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    material_index: usize,
) ![]const u8 {
    const filename = try std.fmt.allocPrint(
        allocator,
        "material.{d}.mat",
        .{material_index},
    );
    defer allocator.free(filename);

    return try getOutputFileName(allocator, output_dir, filename);
}

fn getOutputTextureFileName(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    material_index: usize,
    texture_index: usize,
) ![]const u8 {
    const filename = try std.fmt.allocPrint(
        allocator,
        "material.{d}.{d}.ktx",
        .{ material_index, texture_index },
    );
    defer allocator.free(filename);

    return try getOutputFileName(allocator, output_dir, filename);
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
        .output_dir = if (res.positionals[1]) |value| value else return invalidArgument(std_err, "OUT_DIR"),
        .conversion_options = .{},
    };

    if (res.args.compression != 0) {
        options.conversion_options.compression = true;
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

    try std_out.print("Material compiler:\n", .{});
    try std_out.print("  - Input file: {s}\n", .{options.input_file});
    try std_out.print("  - Output dir: {s}\n", .{options.output_dir});
    try std_out.print("  - Compression: {}\n", .{options.conversion_options.compression});
    try std_out.print("  - Compression level: {d}\n", .{options.conversion_options.level});
    try std_out.print("  - Compression quality: {d}\n", .{options.conversion_options.quality});
    try std_out.print("  - Threads: {d}\n", .{if (options.conversion_options.threads) |value| value else 0});
    try std_out.print("  - Mipmaps generation: {}\n", .{options.conversion_options.mipmaps});
    try std_out.print("  - Edge: {s}\n", .{options.conversion_options.edge.name()});
    try std_out.print("  - Filter: {s}\n", .{options.conversion_options.filter.name()});

    const source = try gltf.Gltf.load(
        allocator,
        options.input_file,
    );
    defer source.deinit();

    if (std.fs.path.isAbsolute(options.output_dir)) {
        std.fs.makeDirAbsolute(options.output_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                std.log.err("Unable to make output directory: {s}", .{@errorName(err)});
                return err;
            }
        };
    } else {
        std.fs.cwd().makeDir(options.output_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                std.log.err("Unable to make output directory: {s}", .{@errorName(err)});
                return err;
            }
        };
    }

    const base_path = std.fs.path.dirname(options.input_file) orelse ".";

    for (0..source.materialCount()) |material_index| {
        const converted_material = try materialc.convert(
            allocator,
            &source,
            base_path,
            material_index,
            options.conversion_options,
        );
        defer converted_material.deinit();

        const material_data = converted_material.material_data;
        try std_out.print("Material {d}:\n", .{material_index});

        try std_out.print("  - Has PBR metallic roughness: {}\n", .{material_data.pbr_metallic_roughness != null});
        if (material_data.pbr_metallic_roughness) |pbr_metallic_roughness| {
            try std_out.print("  - Base color texture index: {?}\n", .{pbr_metallic_roughness.base_color_texture_index});
            try std_out.print("  - Base color factor: [{d}, {d}, {d}, {d}]\n", .{
                pbr_metallic_roughness.base_color_factor[0],
                pbr_metallic_roughness.base_color_factor[1],
                pbr_metallic_roughness.base_color_factor[2],
                pbr_metallic_roughness.base_color_factor[3],
            });
            try std_out.print("  - Metallic roughness texture index: {?}\n", .{pbr_metallic_roughness.metallic_roughness_texture_index});
            try std_out.print("  - Metallic factor: {d}\n", .{pbr_metallic_roughness.metallic_factor});
            try std_out.print("  - Roughness factor: {d}\n", .{pbr_metallic_roughness.roughness_factor});
        }

        try std_out.print("  - Has PBR specular glossiness: {}\n", .{material_data.pbr_specular_glossiness != null});
        if (material_data.pbr_specular_glossiness) |pbr_specular_glossiness| {
            try std_out.print("  - Diffuse texture index: {?}\n", .{pbr_specular_glossiness.diffuse_texture_index});
            try std_out.print("  - Diffuse factor: [{d}, {d}, {d}, {d}]\n", .{
                pbr_specular_glossiness.diffuse_factor[0],
                pbr_specular_glossiness.diffuse_factor[1],
                pbr_specular_glossiness.diffuse_factor[2],
                pbr_specular_glossiness.diffuse_factor[3],
            });
            try std_out.print("  - Specular glossiness texture index: {?}\n", .{pbr_specular_glossiness.specular_glossiness_texture_index});
            try std_out.print("  - Specular factor: [{d}, {d}, {d}]\n", .{
                pbr_specular_glossiness.specular_factor[0],
                pbr_specular_glossiness.specular_factor[1],
                pbr_specular_glossiness.specular_factor[2],
            });
            try std_out.print("  - Glossiness factor: {d}\n", .{pbr_specular_glossiness.glossiness_factor});
        }

        try std_out.print("  - Normal texture index: {?}\n", .{material_data.normal_texture_index});
        try std_out.print("  - Occlusion texture index: {?}\n", .{material_data.occlusion_texture_index});
        try std_out.print("  - Emissive texture index: {?}\n", .{material_data.emissive_texture_index});
        try std_out.print("  - Emissive factor: [{d}, {d}, {d}]\n", .{
            material_data.emissive_factor[0],
            material_data.emissive_factor[1],
            material_data.emissive_factor[2],
        });
        try std_out.print("  - Alpha mode: {s}\n", .{material_data.alpha_mode.name()});
        try std_out.print("  - Alpha cutoff: {d}\n", .{material_data.alpha_cutoff});
        try std_out.print("  - Double sided: {}\n", .{material_data.double_sided});

        const material_filename = try getOutputMaterialFileName(
            allocator,
            options.output_dir,
            material_index,
        );
        defer allocator.free(material_filename);

        try materialc.saveMaterialData(
            material_filename,
            &material_data,
        );

        for (converted_material.textures.items, 0..) |texture, texture_index| {
            const texture_filename = try getOutputTextureFileName(
                allocator,
                options.output_dir,
                material_index,
                texture_index,
            );
            defer allocator.free(texture_filename);

            try texture.save(texture_filename);
        }
    }
}
