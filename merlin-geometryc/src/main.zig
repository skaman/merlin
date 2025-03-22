const std = @import("std");

const clap = @import("clap");
const geometryc = @import("geometryc");
const gltf = @import("merlin_gltf");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Options = struct {
    input_file: []const u8,
    output_dir: []const u8,
    conversion_options: geometryc.Options,
};

const Params = clap.parseParamsComptime(
    \\-h, --help                    Display this help and exit.
    \\-n, --normal <ENABLED>        Include normal attribute (1/0). Default is 1.
    \\-t, --tangent <ENABLED>       Include tangent attribute (1/0). Default is 0.
    \\-C, --color <ENABLED>         Include color attribute (1/0). Default is 0.
    \\-w, --weight <ENABLED>        Include weight attribute (1/0). Default is 0.
    \\-T, --tex-coord <ENABLED>     Include texture coordinate attribute (1/0). Default is 1.
    \\<IN_FILE>                     Source file.
    \\<OUT_DIR>                     Output directory.
);

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn printHelp(writer: anytype) !void {
    try writer.print("Usage: merlin-geometryc [options] <IN_FILE> <OUT_FILE>\n", .{});
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

fn getOutputFileName(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    filename: []const u8,
) ![]const u8 {
    return try std.fs.path.join(allocator, &[_][]const u8{ output_dir, filename });
}

fn getOutputVertexBufferFileName(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    mesh_index: usize,
    primitive_index: usize,
) ![]const u8 {
    const filename = try std.fmt.allocPrint(
        allocator,
        "vertex.{d}.{d}.bin",
        .{ mesh_index, primitive_index },
    );
    defer allocator.free(filename);

    return try getOutputFileName(allocator, output_dir, filename);
}

fn getOutputIndexBufferFileName(
    allocator: std.mem.Allocator,
    output_dir: []const u8,
    mesh_index: usize,
    primitive_index: usize,
) ![]const u8 {
    const filename = try std.fmt.allocPrint(
        allocator,
        "index.{d}.{d}.bin",
        .{ mesh_index, primitive_index },
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
        .IN_FILE = clap.parsers.string,
        .OUT_DIR = clap.parsers.string,
        .ENABLED = clap.parsers.int(u1, 10),
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

    if (res.args.normal) |value| {
        options.conversion_options.attribute_normal = value != 0;
    }
    if (res.args.tangent) |value| {
        options.conversion_options.attribute_tangent = value != 0;
    }
    if (res.args.color) |value| {
        options.conversion_options.attribute_color = value != 0;
    }
    if (res.args.weight) |value| {
        options.conversion_options.attribute_weight = value != 0;
    }
    if (res.args.@"tex-coord") |value| {
        options.conversion_options.attribute_tex_coord = value != 0;
    }

    try std_out.print("Mesh options:\n", .{});
    try std_out.print("  - Input file: {s}\n", .{options.input_file});
    try std_out.print("  - Output dir: {s}\n", .{options.output_dir});
    try std_out.print("Selected attributes:\n", .{});
    try std_out.print("  - Position\n", .{});
    if (options.conversion_options.attribute_normal) {
        try std_out.print("  - Normal\n", .{});
    }
    if (options.conversion_options.attribute_tangent) {
        try std_out.print("  - Tangent\n", .{});
    }
    if (options.conversion_options.attribute_color) {
        try std_out.print("  - Color\n", .{});
    }
    if (options.conversion_options.attribute_weight) {
        try std_out.print("  - Weight\n", .{});
    }
    if (options.conversion_options.attribute_tex_coord) {
        try std_out.print("  - Texture Coordinate\n", .{});
    }

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

    for (0..source.meshCount()) |mesh_index| {
        const mesh = source.mesh(mesh_index);

        for (0..mesh.primitiveCount()) |primitive_index| {
            try std_out.print("Mesh Informations (Primitive {d}):\n", .{primitive_index});

            const vertex_buffer_name = try getOutputVertexBufferFileName(
                allocator,
                options.output_dir,
                mesh_index,
                primitive_index,
            );
            defer allocator.free(vertex_buffer_name);

            const index_buffer_name = try getOutputIndexBufferFileName(
                allocator,
                options.output_dir,
                mesh_index,
                primitive_index,
            );
            defer allocator.free(index_buffer_name);

            const vertex_buffer_data = try geometryc.convertVertexBuffer(
                allocator,
                source,
                mesh_index,
                primitive_index,
                options.conversion_options,
            );
            defer vertex_buffer_data.deinit();

            try std_out.print("  - Vertex Buffer File: {s}\n", .{vertex_buffer_name});
            try std_out.print("  - Vertex Buffer Size: {s}\n", .{std.fmt.fmtIntSizeDec(vertex_buffer_data.data.len)});
            try std_out.print("  - Vertex Buffer Elements Count: {d}\n", .{vertex_buffer_data.num_vertices});

            try geometryc.saveVertexFile(
                vertex_buffer_name,
                &vertex_buffer_data,
            );

            const index_buffer_data = try geometryc.convertIndexBuffer(
                allocator,
                source,
                mesh_index,
                primitive_index,
            );
            defer index_buffer_data.deinit();

            try std_out.print("  - Index Buffer File: {s}\n", .{index_buffer_name});
            try std_out.print("  - Index Buffer Size: {s}\n", .{std.fmt.fmtIntSizeDec(index_buffer_data.data.len)});
            try std_out.print("  - Index Buffer Type: {s}\n", .{index_buffer_data.index_type.name()});
            try std_out.print("  - Index Buffer Elements Count: {d}\n", .{index_buffer_data.num_indices});

            try geometryc.saveIndexFile(
                index_buffer_name,
                &index_buffer_data,
            );
        }
    }
}
