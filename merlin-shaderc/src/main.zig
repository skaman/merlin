const std = @import("std");

const clap = @import("clap");
const shaderc = @import("shaderc");

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

const Params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit.
    \\<IN_FILE>              Source file.
    \\<OUT_FILE>             Source file.
);

pub fn printHelp() !void {
    std.debug.print("Usage: merlin-shaderc [options] <IN_FILE> <OUT_FILE>\n", .{});
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
        .IN_FILE = clap.parsers.string,
        .OUT_FILE = clap.parsers.string,
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

    const input_file = res.positionals[0];
    if (input_file == null) {
        return printHelp();
    }

    const output_file = res.positionals[1];
    if (output_file == null) {
        return printHelp();
    }

    const std_out = std.io.getStdOut().writer();
    const shader_type = try shaderc.detectShaderType(input_file.?);

    try std_out.print("Compiling {s} ({s})\n", .{
        input_file.?,
        switch (shader_type) {
            .vertex => "vertex",
            .fragment => "fragment",
        },
    });

    const file_content = try readFile(allocator, input_file.?);
    defer allocator.free(file_content);

    const data = try shaderc.compile(
        allocator,
        input_file.?,
        file_content,
    );
    defer data.deinit();

    if (data.input_attributes) |input_attributes| {
        try std_out.print("Input attributes:\n", .{});
        for (input_attributes.input_variables) |input_var| {
            try std_out.print("  - {s} (location={d})\n", .{ input_var.name, input_var.location });
        }
    }

    for (data.descriptor_sets.sets) |descriptor_set| {
        try std_out.print("Descriptor set {d}:\n", .{descriptor_set.set});
        for (descriptor_set.bindings) |binding| {
            try std_out.print("  - {s} (binding={d}, type={s}, size={s})\n", .{
                binding.name,
                binding.binding,
                binding.type.name(),
                std.fmt.fmtIntSizeDec(binding.size),
            });
        }
    }

    try std_out.print("Push constants:\n", .{});
    for (data.push_constants.items) |push_constant| {
        try std_out.print("  - {s} (offset={d}, size={d})\n", .{
            push_constant.name,
            push_constant.offset,
            push_constant.size,
        });
    }

    try std_out.print("Saving {s}\n", .{output_file.?});
    try shaderc.save(
        output_file.?,
        data,
    );
}
