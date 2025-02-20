const std = @import("std");

const clap = @import("clap");

const c = @cImport({
    @cInclude("shaderc/shaderc.h");
});

pub fn preprocessHeader(
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

    const result = c.shaderc_compile_into_preprocessed_text(
        compiler,
        source.ptr,
        source.len,
        kind,
        filename_sentinel,
        "main",
        options,
    );

    const status = c.shaderc_result_get_compilation_status(result);
    if (status != c.shaderc_compilation_status_success) {
        const message = c.shaderc_result_get_error_message(result);
        std.log.err("{s}\n", .{message});
        return error.CompilerError;
    }

    const output = try allocator.alloc(u8, c.shaderc_result_get_length(result));
    const bytes = c.shaderc_result_get_bytes(result);
    @memcpy(output, std.mem.sliceTo(bytes, 0));
    return output;
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
        // Report useful error and exit.
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

    //if (res.args.output) |s|
    //    std.debug.print("--output = {s}\n", .{s});

    std.log.info("Compiling {s}...", .{source_file.?});

    var file = try std.fs.cwd().openFile(source_file.?, .{});
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(file_content);
    std.debug.print("{s}", .{file_content});

    const output = try preprocessHeader(
        allocator,
        source_file.?,
        c.shaderc_glsl_vertex_shader,
        file_content,
    );
    defer allocator.free(output);

    std.log.info("{s}", .{output});
}
