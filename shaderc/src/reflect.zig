const std = @import("std");

const shared = @import("shared");

const c = @cImport({
    @cInclude("spirv_reflect.h");
});

//pub const Variable = struct {
//    attribute: shared.Attribute,
//};

const AttributeMapEntry = struct {
    name: []const u8,
    attribute: shared.Attribute,
};

const AttributeMap = [_]AttributeMapEntry{
    AttributeMapEntry{ .name = "a_position", .attribute = .position },
    AttributeMapEntry{ .name = "a_normal", .attribute = .normal },
    AttributeMapEntry{ .name = "a_tangent", .attribute = .tangent },
    AttributeMapEntry{ .name = "a_bitangent", .attribute = .bitangent },
    AttributeMapEntry{ .name = "a_color0", .attribute = .color_0 },
    AttributeMapEntry{ .name = "a_color1", .attribute = .color_1 },
    AttributeMapEntry{ .name = "a_color2", .attribute = .color_2 },
    AttributeMapEntry{ .name = "a_color3", .attribute = .color_3 },
    AttributeMapEntry{ .name = "a_indices", .attribute = .indices },
    AttributeMapEntry{ .name = "a_weight", .attribute = .weight },
    AttributeMapEntry{ .name = "a_texcoord0", .attribute = .tex_coord_0 },
    AttributeMapEntry{ .name = "a_texcoord1", .attribute = .tex_coord_1 },
    AttributeMapEntry{ .name = "a_texcoord2", .attribute = .tex_coord_2 },
    AttributeMapEntry{ .name = "a_texcoord3", .attribute = .tex_coord_3 },
    AttributeMapEntry{ .name = "a_texcoord4", .attribute = .tex_coord_4 },
    AttributeMapEntry{ .name = "a_texcoord5", .attribute = .tex_coord_5 },
    AttributeMapEntry{ .name = "a_texcoord6", .attribute = .tex_coord_6 },
    AttributeMapEntry{ .name = "a_texcoord7", .attribute = .tex_coord_7 },
};

pub const ShaderReflect = struct {
    shader_module: c.SpvReflectShaderModule,

    pub fn init(data: []const u8) !ShaderReflect {
        var shader_module: c.SpvReflectShaderModule = undefined;
        if (c.spvReflectCreateShaderModule(
            data.len,
            data.ptr,
            &shader_module,
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            return error.OutOfMemory;
        }

        return ShaderReflect{
            .shader_module = shader_module,
        };
    }

    pub fn deinit(self: *ShaderReflect) void {
        c.spvReflectDestroyShaderModule(&self.shader_module);
    }

    //pub fn getEntryPointName(self: *ShaderReflect) ![]const u8 {
    //    return self.shader_module.entry_point_name;
    //}

    pub fn getInputAttributes(self: *ShaderReflect, allocator: std.mem.Allocator) ![]?shared.Attribute {
        var input_variable_count: u32 = 0;
        if (c.spvReflectEnumerateInputVariables(
            &self.shader_module,
            &input_variable_count,
            null,
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate input variables", .{});
            return error.FailedEnumerateInputVariables;
        }

        const input_variables = try allocator.alloc(
            *c.SpvReflectInterfaceVariable,
            input_variable_count,
        );
        defer allocator.free(input_variables);

        if (c.spvReflectEnumerateInputVariables(
            &self.shader_module,
            &input_variable_count,
            @ptrCast(input_variables.ptr),
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate input variables", .{});
            return error.FailedEnumerateInputVariables;
        }

        const result = try allocator.alloc(
            ?shared.Attribute,
            input_variable_count,
        );
        errdefer allocator.free(result);

        for (input_variables, 0..) |input, i| {
            var attribute: ?shared.Attribute = null;
            for (AttributeMap) |entry| {
                if (std.mem.eql(u8, std.mem.sliceTo(input.name, 0), entry.name)) {
                    attribute = entry.attribute;
                    break;
                }
            }

            result[i] = attribute;
        }

        return result;
    }

    //pub fn getDescriptorSets(self: *ShaderReflect) ![]const *c.SpvReflectDescriptorSet {
    //    var descriptor_set_count: u32 = 0;
    //    if (c.spvReflectEnumerateDescriptorSets(
    //        &self.shader_module,
    //        &descriptor_set_count,
    //        null,
    //    ) != c.SPV_REFLECT_RESULT_SUCCESS) {
    //        return error.ReflectError;
    //    }

    //    const descriptor_sets = try self.allocator.alloc(*c.SpvReflectDescriptorSet, descriptor_set_count);
    //    errdefer self.allocator.free(descriptor_sets);

    //    if (c.spvReflectEnumerateDescriptorSets(
    //        &self.shader_module,
    //        &descriptor_set_count,
    //        @ptrCast(descriptor_sets.ptr),
    //    ) != c.SPV_REFLECT_RESULT_SUCCESS) {
    //        return error.ReflectError;
    //    }

    //    return descriptor_sets;
    //}
};
