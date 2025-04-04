const std = @import("std");

const clap = @import("clap");
const geometryc = @import("geometryc");
const gltf = @import("merlin_gltf");
const utils = @import("merlin_utils");
const asset_types = utils.asset_types;

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Options = struct {
    input_file: []const u8,
    output_file: []const u8,
    sub_mesh_index: usize,
    conversion_options: geometryc.Options,
};

const Params = clap.parseParamsComptime(
    \\-h, --help                    Display this help and exit.
    \\-n, --normal <ENABLED>        Include normal attribute (1/0). Default is 1.
    \\-t, --tangent <ENABLED>       Include tangent attribute (1/0). Default is 0.
    \\-C, --color <ENABLED>         Include color attribute (1/0). Default is 0.
    \\-w, --weight <ENABLED>        Include weight attribute (1/0). Default is 0.
    \\-T, --tex-coord <ENABLED>     Include texture coordinate attribute (1/0). Default is 1.
    \\-s, --sub-mesh <INDEX>        Sub-mesh index to convert.
    \\<IN_FILE>                     Source file.
    \\<OUT_FILE>                    Output directory.
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
        .ENABLED = clap.parsers.int(u1, 10),
        .INDEX = clap.parsers.int(usize, 10),
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
        .sub_mesh_index = if (res.args.@"sub-mesh") |value| value else 0,
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
    try std_out.print("  - Output file: {s}\n", .{options.output_file});
    try std_out.print("  - Sub-mesh index: {d}\n", .{options.sub_mesh_index});
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

    const source = try gltf.Gltf.load(allocator, options.input_file);
    defer source.deinit();

    if (options.sub_mesh_index >= source.meshCount()) {
        std.log.err("Sub-mesh index out of bounds\n", .{});
        return error.InvalidArgument;
    }

    const mesh = source.mesh(options.sub_mesh_index);

    if (mesh.primitiveCount() > 1) {
        std.log.err("Multiple primitives are not supported yet\n", .{});
        return error.Unsupported;
    }

    const primitive_index = 0;
    try std_out.print("Mesh Informations (Primitive {d}):\n", .{primitive_index});

    const vertex_buffer_data = try geometryc.convertVertexBuffer(
        allocator,
        source,
        options.sub_mesh_index,
        primitive_index,
        options.conversion_options,
    );
    defer vertex_buffer_data.deinit();

    try std_out.print("  - Vertex Buffer Size: {s}\n", .{std.fmt.fmtIntSizeDec(vertex_buffer_data.data.len)});
    try std_out.print("  - Vertex Buffer Elements Count: {d}\n", .{vertex_buffer_data.num_vertices});

    const index_buffer_data = try geometryc.convertIndexBuffer(
        allocator,
        source,
        options.sub_mesh_index,
        primitive_index,
    );
    defer index_buffer_data.deinit();

    try std_out.print("  - Index Buffer Size: {s}\n", .{std.fmt.fmtIntSizeDec(index_buffer_data.data.len)});
    try std_out.print("  - Index Buffer Type: {s}\n", .{index_buffer_data.index_type.name()});
    try std_out.print("  - Index Buffer Elements Count: {d}\n", .{index_buffer_data.num_indices});

    const mesh_data = asset_types.MeshData{
        .vertex_layout = vertex_buffer_data.layout,
        .vertices_count = @intCast(vertex_buffer_data.num_vertices),
        .vertices_data_size = @intCast(vertex_buffer_data.data.len),
        .index_type = index_buffer_data.index_type,
        .indices_count = @intCast(index_buffer_data.num_indices),
        .indices_data_size = @intCast(index_buffer_data.data.len),
    };

    try geometryc.saveMeshData(
        options.output_file,
        &mesh_data,
        vertex_buffer_data.data,
        index_buffer_data.data,
    );
}
