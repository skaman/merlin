const std = @import("std");

const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;

const c = @import("c.zig").c;
const reflect = @import("reflect.zig");

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

const StageExtensionMapEntry = struct {
    stage: gfx_types.ShaderType,
    extension: []const u8,
};

const StageExtensionMap = [_]StageExtensionMapEntry{
    .{ .stage = .vertex, .extension = ".vert" },
    .{ .stage = .fragment, .extension = ".frag" },
};

const StageMap = [@typeInfo(gfx_types.ShaderType).@"enum".fields.len]c.shaderc_shader_kind{
    c.shaderc_glsl_vertex_shader,
    c.shaderc_glsl_fragment_shader,
};

pub const CompiledShader = struct {
    allocator: std.mem.Allocator,
    type: gfx_types.ShaderType,
    data: []align(@alignOf(u32)) const u8,
    input_attributes: ?reflect.InputAttributes,
    descriptor_sets: reflect.DescriptorSets,
    shader_type: gfx_types.ShaderType,

    pub fn deinit(self: *const CompiledShader) void {
        self.allocator.free(self.data);
        if (self.input_attributes) |iattr| {
            iattr.deinit();
        }
        self.descriptor_sets.deinit();
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn compileShader(
    allocator: std.mem.Allocator,
    filename: []const u8,
    kind: c.shaderc_shader_kind,
    source: []const u8,
) ![]align(@alignOf(u32)) const u8 {
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

    const output = try allocator.alignedAlloc(u8, @alignOf(u32), size);
    const bytes = c.shaderc_result_get_bytes(result);
    @memcpy(output, bytes[0..size]);
    return output;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn detectShaderType(source_file: []const u8) !gfx_types.ShaderType {
    for (StageExtensionMap) |map_entry| {
        if (std.mem.endsWith(u8, source_file, map_entry.extension)) {
            return map_entry.stage;
        }
    }
    return error.UnknownShaderType;
}

pub fn compile(allocator: std.mem.Allocator, filename: []const u8, file_content: []const u8) !CompiledShader {
    const shader_type = try detectShaderType(filename);

    const data = try compileShader(
        allocator,
        filename,
        StageMap[@intFromEnum(shader_type)],
        file_content,
    );
    errdefer allocator.free(data);

    var shader_reflect = try reflect.ShaderReflect.init(data);
    defer shader_reflect.deinit();

    var input_attributes = switch (shader_type) {
        .vertex => try shader_reflect.inputAttributes(allocator),
        else => null,
    };
    errdefer {
        if (input_attributes) |*iattr| {
            iattr.deinit();
        }
    }

    const descriptor_sets = try shader_reflect.descriptorSets(allocator);
    errdefer descriptor_sets.deinit();

    return .{
        .allocator = allocator,
        .type = shader_type,
        .data = data,
        .input_attributes = input_attributes,
        .descriptor_sets = descriptor_sets,
        .shader_type = shader_type,
    };
}

pub fn save(
    path: []const u8,
    compiled_shader: CompiledShader,
) !void {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const shader_data = gfx_types.ShaderData{
        .type = compiled_shader.shader_type,
        .data = compiled_shader.data,
        .input_attributes = if (compiled_shader.input_attributes) |attrs| attrs.attributes else &[0]gfx_types.ShaderInputAttribute{},
        .descriptor_sets = compiled_shader.descriptor_sets.sets,
    };

    try utils.Serializer.writeHeader(
        file.writer(),
        gfx_types.ShaderMagic,
        gfx_types.ShaderVersion,
    );
    try utils.Serializer.write(file.writer(), shader_data);
}
