const std = @import("std");

const clap = @import("clap");
const mcl = @import("merlin_core_layer");
const gfx = mcl.gfx;

const reflect = @import("reflect.zig");

const c = @cImport({
    @cInclude("shaderc/shaderc.h");
    @cInclude("spirv_reflect.h");
});

fn compileShader(
    allocator: std.mem.Allocator,
    filename: []const u8,
    kind: c.shaderc_shader_kind,
    source: []const u8,
) ![]const u8 {
    const compiler = c.shaderc_compiler_initialize();
    defer c.shaderc_compiler_release(compiler);

    const options = c.shaderc_compile_options_initialize();
    defer c.shaderc_compile_options_release(options);

    const filename_sentinel = try allocator.dupeZ(u8, filename);
    defer allocator.free(filename_sentinel);

    const result = c.shaderc_compile_into_spv(
        compiler,
        source.ptr,
        source.len,
        kind,
        filename_sentinel,
        "main",
        options,
    );
    defer c.shaderc_result_release(result);

    const status = c.shaderc_result_get_compilation_status(result);
    if (status != c.shaderc_compilation_status_success) {
        const message = c.shaderc_result_get_error_message(result);
        std.log.err("{s}\n", .{message});
        return error.CompilerError;
    }

    const size = c.shaderc_result_get_length(result);

    const output = try allocator.alloc(u8, size);
    const bytes = c.shaderc_result_get_bytes(result);
    @memcpy(output, bytes[0..size]);
    return output;
}

pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

pub fn saveFile(path: []const u8, shader_type: gfx.ShaderType, data: []const u8, input_attributes: []?gfx.Attribute) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const writer = file.writer();
    try writer.writeAll(&gfx.ShaderMagic);
    try writer.writeInt(u8, gfx.ShaderVersion, .little);
    try writer.writeInt(u8, @intFromEnum(shader_type), .little);
    try writer.writeInt(u32, @intCast(data.len), .little);
    try writer.writeAll(data);
    if (shader_type == .vertex) {
        try writer.writeInt(u8, @intCast(input_attributes.len), .little);
        for (input_attributes) |attribute| {
            try writer.writeInt(u8, @intFromBool(attribute != null), .little);
            if (attribute == null) {
                continue;
            }
            try writer.writeInt(u8, @intFromEnum(attribute.?), .little);
        }
    }
}

const Params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\-o, --output <FILE>    Write output to <FILE>.
    \\<FILE>                 Source file.
    \\
);

pub fn printHelp() !void {
    std.debug.print("Usage: shaderc [options] <source file>\n", .{});
    return clap.help(
        std.io.getStdErr().writer(),
        clap.Help,
        &Params,
        .{ .description_on_new_line = false, .spacing_between_parameters = 0 },
    );
}

const StageExtensionMapEntry = struct {
    stage: gfx.ShaderType,
    extension: []const u8,
};

const StageExtensionMap = [_]StageExtensionMapEntry{
    .{ .stage = .vertex, .extension = ".vert" },
    .{ .stage = .fragment, .extension = ".frag" },
};

const StageMap = [@typeInfo(gfx.ShaderType).@"enum".fields.len]c.shaderc_shader_kind{
    c.shaderc_glsl_vertex_shader,
    c.shaderc_glsl_fragment_shader,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const parsers = comptime .{
        .FILE = clap.parsers.string,
        //.str = clap.parsers.string,
        //.usize = clap.parsers.int(usize, 0),
    };

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &Params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return printHelp();
    }

    const source_file = res.positionals[0];
    if (source_file == null) {
        return printHelp();
    }

    //std.log.info("Compiling {s}...", .{source_file.?});

    var shader_type: ?gfx.ShaderType = null;
    for (StageExtensionMap) |map_entry| {
        if (std.mem.endsWith(u8, source_file.?, map_entry.extension)) {
            shader_type = map_entry.stage;
            break;
        }
    }
    if (shader_type == null) {
        std.log.err("Unknown shader type", .{});
        return error.UnknownShaderType;
    }

    const file_content = try readFile(allocator, source_file.?);
    defer allocator.free(file_content);

    const data = try compileShader(
        allocator,
        source_file.?,
        StageMap[@intFromEnum(shader_type.?)],
        file_content,
    );
    defer allocator.free(data);

    var shader_reflect = try reflect.ShaderReflect.init(data);
    defer shader_reflect.deinit();

    const input_attributes = try shader_reflect.getInputAttributes(allocator);
    defer allocator.free(input_attributes);

    //var shader_data = try shared.ShaderData.init(
    //    allocator,
    //    shader_type.?,
    //    data,
    //    input_attributes,
    //);
    //defer shader_data.deinit();

    if (res.args.output) |s| {
        try saveFile(s, shader_type.?, data, input_attributes);
    }
}
