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
    push_constants: reflect.PushConstants,
    shader_type: gfx_types.ShaderType,

    pub fn deinit(self: *const CompiledShader) void {
        self.allocator.free(self.data);
        if (self.input_attributes) |iattr| {
            iattr.deinit();
        }
        self.descriptor_sets.deinit();
        self.push_constants.deinit();
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

const IncludeUserData = struct {
    allocator: std.mem.Allocator,
    include_paths: []const []const u8,
};

const IncludeUserDataResponse = struct {
    allocator: std.mem.Allocator,
    source_name: []const u8,
    content: []const u8,
    result: c.shaderc_include_result,
};

fn fileExists(path: []const u8) bool {
    std.fs.accessAbsolute(path, .{}) catch return false;
    return true;
}

fn resolveRelativeIncludePath(
    allocator: std.mem.Allocator,
    requested_source: []const u8,
    requesting_source: []const u8,
) ![]const u8 {
    const base_path = std.fs.path.dirname(requesting_source) orelse return error.InvalidPath;
    const joined_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ base_path, requested_source },
    );
    errdefer allocator.free(joined_path);

    if (!fileExists(joined_path)) {
        return error.IncludeFileFound;
    }
    return joined_path;
}

fn resolveStadardIncludePath(
    allocator: std.mem.Allocator,
    requested_source: []const u8,
    include_paths: []const []const u8,
) ![]const u8 {
    for (include_paths) |path| {
        const joined_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ path, requested_source },
        );

        if (fileExists(joined_path)) {
            return joined_path;
        }

        allocator.free(joined_path);
    }

    return error.IncludeFileNotFound;
}

fn readFileContent(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) ![]const u8 {
    var file = try std.fs.openFileAbsolute(file_path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, 4096 * 1024);
}

fn includeResolve(
    user_data: ?*anyopaque,
    requested_source: [*c]const u8,
    type_: c_int,
    requesting_source: [*c]const u8,
    _: usize,
) callconv(.c) [*c]c.shaderc_include_result {
    const include_user_data: *IncludeUserData = @ptrCast(@alignCast(user_data.?));
    var file_path: ?[]const u8 = null;

    const requested_source_slice = requested_source[0..std.mem.len(requested_source)];
    const requesting_source_slice = requesting_source[0..std.mem.len(requesting_source)];

    if (type_ == c.shaderc_include_type_relative) {
        file_path = resolveRelativeIncludePath(
            include_user_data.allocator,
            requested_source_slice,
            requesting_source_slice,
        ) catch |err| {
            std.log.err("Failed to resolve relative include path: {any}", .{err});
            return null;
        };
    } else if (type_ == c.shaderc_include_type_standard) {
        file_path = resolveStadardIncludePath(
            include_user_data.allocator,
            requested_source_slice,
            include_user_data.include_paths,
        ) catch |err| {
            std.log.err("Failed to resolve absolute include path: {any}", .{err});
            return null;
        };
    } else {
        @panic("Unsupported include type");
    }

    if (file_path == null) {
        std.log.err("Include file not found: {s}", .{requested_source});
        return null;
    }

    const content = readFileContent(
        include_user_data.allocator,
        file_path.?,
    ) catch |err| {
        std.log.err("Failed to read include file: {s}, error: {any}", .{ file_path.?, err });
        return null;
    };

    const user_data_response =
        include_user_data.allocator.create(IncludeUserDataResponse) catch |err| {
            std.log.err("Failed to allocate user data response: {any}", .{err});
            return null;
        };

    user_data_response.* = IncludeUserDataResponse{
        .allocator = include_user_data.allocator,
        .source_name = file_path.?,
        .content = content,
        .result = .{
            .source_name = file_path.?.ptr,
            .source_name_length = @intCast(file_path.?.len),
            .content = content.ptr,
            .content_length = content.len,
            .user_data = @ptrCast(user_data_response),
        },
    };
    return @ptrCast(&user_data_response.*.result);
}

fn includeRelease(
    _: ?*anyopaque,
    result: [*c]c.shaderc_include_result,
) callconv(.c) void {
    const response: *IncludeUserDataResponse = @ptrCast(@alignCast(result.*.user_data.?));
    response.allocator.free(response.source_name);
    response.allocator.free(response.content);
    response.allocator.destroy(response);
}

fn compileShader(
    allocator: std.mem.Allocator,
    filename: []const u8,
    kind: c.shaderc_shader_kind,
    source: []const u8,
    include_paths: []const []const u8,
) ![]align(@alignOf(u32)) const u8 {
    const compiler = c.shaderc_compiler_initialize();
    defer c.shaderc_compiler_release(compiler);

    const options = c.shaderc_compile_options_initialize();
    defer c.shaderc_compile_options_release(options);

    var include_user_data = IncludeUserData{
        .allocator = allocator,
        .include_paths = include_paths,
    };
    c.shaderc_compile_options_set_include_callbacks(
        options,
        &includeResolve,
        &includeRelease,
        @ptrCast(&include_user_data),
    );

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

pub fn compile(
    allocator: std.mem.Allocator,
    filename: []const u8,
    file_content: []const u8,
    include_paths: []const []const u8,
) !CompiledShader {
    const shader_type = try detectShaderType(filename);

    const data = try compileShader(
        allocator,
        filename,
        StageMap[@intFromEnum(shader_type)],
        file_content,
        include_paths,
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

    const push_constants = try shader_reflect.pushConstants(allocator);
    errdefer push_constants.deinit();

    return .{
        .allocator = allocator,
        .type = shader_type,
        .data = data,
        .input_attributes = input_attributes,
        .descriptor_sets = descriptor_sets,
        .push_constants = push_constants,
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
        .push_constants = compiled_shader.push_constants.items,
    };

    try utils.Serializer.writeHeader(
        file.writer(),
        gfx_types.ShaderMagic,
        gfx_types.ShaderVersion,
    );
    try utils.Serializer.write(file.writer(), shader_data);
}
