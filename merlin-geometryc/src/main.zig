const std = @import("std");

const clap = @import("clap");
const gfx = @import("merlin_gfx");
const utils = @import("merlin_utils");

const c = @import("c.zig").c;
const converter = @import("converter.zig");
const Gltf = @import("gltf.zig").Gltf;

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Options = struct {
    input_file: []const u8,
    output_file: []const u8,
    mesh_index: usize,
    normal: bool,
    tangent: bool,
    color: bool,
    weight: bool,
    tex_coord: bool,
};

const Params = clap.parseParamsComptime(
    \\-h, --help                Display this help and exit.
    \\-c, --mesh <INDEX>        Mesh index to extract. Default is 0.
    \\-n, --normal              Include normal attribute.
    \\-t, --tangent             Include tangent attribute.
    \\-C, --color               Include color attribute.
    \\-w, --weight              Include weight attribute.
    \\-T, --tex-coord           Include texture coordinate attribute.
    \\<IN_FILE>                 Source file.
    \\<OUT_FILE>                Output file.
);

// *********************************************************************************************
// Private API
// *********************************************************************************************

pub fn saveVertexFile(
    path: []const u8,
    data: []const u8,
    vertex_layout: gfx.VertexLayout,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try utils.Serializer.writeHeader(file.writer(), gfx.VertexBufferMagic, gfx.VertexBufferVersion);
    try utils.Serializer.write(file.writer(), vertex_layout);
    try utils.Serializer.write(file.writer(), data);
}

pub fn saveIndexFile(
    path: []const u8,
    data: []const u8,
    index_type: gfx.IndexType,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try utils.Serializer.writeHeader(file.writer(), gfx.IndexBufferMagic, gfx.IndexBufferVersion);
    try utils.Serializer.write(file.writer(), index_type);
    try utils.Serializer.write(file.writer(), data);
}

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

fn getVertexBufferName(
    allocator: std.mem.Allocator,
    mesh_filename: []const u8,
    primitive_index: usize,
) ![]const u8 {
    const basename = std.fs.path.stem(mesh_filename);
    const path = std.fs.path.dirname(mesh_filename) orelse ".";
    const filename = try std.fmt.allocPrint(
        allocator,
        "{s}.vertex.{d}.bin",
        .{ basename, primitive_index },
    );
    defer allocator.free(filename);

    return try std.fs.path.join(allocator, &[_][]const u8{ path, filename });
}

fn getIndexBufferName(
    allocator: std.mem.Allocator,
    mesh_filename: []const u8,
    primitive_index: usize,
) ![]const u8 {
    const basename = std.fs.path.stem(mesh_filename);
    const path = std.fs.path.dirname(mesh_filename) orelse ".";
    const filename = try std.fmt.allocPrint(
        allocator,
        "{s}.index.{d}.bin",
        .{ basename, primitive_index },
    );
    defer allocator.free(filename);

    return try std.fs.path.join(allocator, &[_][]const u8{ path, filename });
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
        .OUT_FILE = clap.parsers.string,
        .INDEX = clap.parsers.int(u32, 10),
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
        .mesh_index = res.args.mesh orelse 0,
        .normal = res.args.normal != 0,
        .tangent = res.args.tangent != 0,
        .color = res.args.color != 0,
        .weight = res.args.weight != 0,
        .tex_coord = res.args.@"tex-coord" != 0,
    };

    try std_out.print("Mesh Options:\n", .{});
    try std_out.print("  - Input File: {s}\n", .{options.input_file});
    try std_out.print("  - Output File: {s}\n", .{options.output_file});
    try std_out.print("  - Mesh Index: {d}\n", .{options.mesh_index});
    try std_out.print("  - Normal: {}\n", .{options.normal});
    try std_out.print("  - Tangent: {}\n", .{options.tangent});
    try std_out.print("  - Color: {}\n", .{options.color});
    try std_out.print("  - Weight: {}\n", .{options.weight});
    try std_out.print("  - Tex Coord: {}\n", .{options.tex_coord});
    try std_out.print("\n", .{});

    try std_out.print("Loading glTF file...\n", .{});
    const gltf = try Gltf.init(
        allocator,
        options.input_file,
    );
    defer gltf.deinit();

    try std_out.print("Creating mesh...\n", .{});
    const mesh = try converter.Mesh.init(
        allocator,
        gltf,
        options.mesh_index,
        options.normal,
        options.tangent,
        options.color,
        options.weight,
        options.tex_coord,
    );
    defer mesh.deinit();

    try std_out.print("\n", .{});
    for (mesh.primitives, 0..) |*primitive, index| {
        try std_out.print("Mesh Informations (Primitive {d}):\n", .{index});
        const vertex_buffer_name = try getVertexBufferName(
            allocator,
            options.output_file,
            index,
        );
        defer allocator.free(vertex_buffer_name);

        const index_buffer_name = try getIndexBufferName(
            allocator,
            options.output_file,
            index,
        );
        defer allocator.free(index_buffer_name);

        try std_out.print("  - Vertex Buffer File: {s}\n", .{vertex_buffer_name});
        try std_out.print("  - Vertex Buffer Size: {s}\n", .{std.fmt.fmtIntSizeDec(primitive.vertex_data.len)});
        try std_out.print("  - Vertex Buffer Stride: {d}\n", .{primitive.vertex_layout.stride});
        try std_out.print("  - Vertex Buffer Elements Count: {d}\n", .{primitive.num_vertices});

        for (primitive.vertex_layout.attributes, 0..) |attribute, attribute_index| {
            const attribute_type: gfx.VertexAttributeType = @enumFromInt(attribute_index);
            if (attribute.num == 0) continue;

            try std_out.print("  - Vertex Buffer Attribute {d}: component={s}, type={s}, num={d}, normalized={}, offset={d}\n", .{
                attribute_index,
                attribute_type.getName(),
                attribute.type.getName(),
                attribute.num,
                attribute.normalized,
                primitive.vertex_layout.offsets[attribute_index],
            });
        }

        try std_out.print("  - Index Buffer File: {s}\n", .{index_buffer_name});
        try std_out.print("  - Index Buffer Size: {s}\n", .{std.fmt.fmtIntSizeDec(primitive.index_data.len)});
        try std_out.print("  - Index Buffer Type: {s}\n", .{primitive.index_type.getName()});
        try std_out.print("  - Index Buffer Elements Count: {d}\n", .{primitive.num_indices});

        try saveVertexFile(
            vertex_buffer_name,
            primitive.vertex_data,
            primitive.vertex_layout,
        );

        try saveIndexFile(
            index_buffer_name,
            primitive.index_data,
            primitive.index_type,
        );
    }
}
