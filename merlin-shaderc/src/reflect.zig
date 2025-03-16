const std = @import("std");

const gfx = @import("merlin_gfx");

const c = @cImport({
    @cInclude("spirv_reflect.h");
});

//pub const Variable = struct {
//    attribute: shared.Attribute,
//};

const AttributeMapEntry = struct {
    name: []const u8,
    attribute: gfx.VertexAttributeType,
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

    pub fn getInputAttributes(
        self: *ShaderReflect,
        allocator: std.mem.Allocator,
        std_out: anytype,
    ) ![]gfx.ShaderInputAttribute {
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
            gfx.ShaderInputAttribute,
            input_variable_count,
        );
        errdefer allocator.free(result);

        try std_out.print("Input variables:\n", .{});
        for (input_variables, 0..) |input, i| {
            try std_out.print("  - {s} (location={d})\n", .{ input.name, input.location });
            var attribute: ?gfx.VertexAttributeType = null;
            for (AttributeMap) |entry| {
                if (std.mem.eql(u8, std.mem.sliceTo(input.name, 0), entry.name)) {
                    attribute = entry.attribute;
                    break;
                }
            }
            if (attribute == null) {
                std.log.err("Unknown input variable {s}", .{input.name});
                return error.UnknownInputVariable;
            }

            result[i] = .{
                .attribute = attribute.?,
                .location = @intCast(i),
            };
        }

        return result;
    }

    pub fn getDescriptorSets(
        self: *ShaderReflect,
        allocator: std.mem.Allocator,
        std_out: anytype,
    ) ![]gfx.DescriptorSet {
        var descriptor_set_count: u32 = 0;
        if (c.spvReflectEnumerateDescriptorSets(
            &self.shader_module,
            &descriptor_set_count,
            null,
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate descriptor sets", .{});
            return error.FailedEnumerateDescriptorSets;
        }

        const descriptor_sets = try allocator.alloc(
            *c.SpvReflectDescriptorSet,
            descriptor_set_count,
        );
        defer allocator.free(descriptor_sets);

        if (c.spvReflectEnumerateDescriptorSets(
            &self.shader_module,
            &descriptor_set_count,
            @ptrCast(descriptor_sets.ptr),
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate descriptor sets", .{});
            return error.FailedEnumerateDescriptorSets;
        }

        const result = try allocator.alloc(
            gfx.DescriptorSet,
            descriptor_set_count,
        );
        errdefer allocator.free(result);

        var loaded_descriptor_sets: u32 = 0;
        errdefer {
            for (0..loaded_descriptor_sets) |i| {
                for (result[i].bindings) |binding| {
                    allocator.free(binding.name);
                }
                allocator.free(result[i].bindings);
            }
        }

        for (descriptor_sets, 0..) |descriptor_set, i| {
            try std_out.print("Descriptor set {d}:\n", .{descriptor_set.set});

            result[i].set = descriptor_set.set;
            result[i].bindings = try parseDescriptorSet(
                allocator,
                descriptor_set,
                std_out,
            );
            loaded_descriptor_sets += 1;
        }

        return result;
    }

    fn parseDescriptorSet(
        allocator: std.mem.Allocator,
        descriptor_set: *c.SpvReflectDescriptorSet,
        std_out: anytype,
    ) ![]gfx.DescriptorBinding {
        const result = try allocator.alloc(
            gfx.DescriptorBinding,
            descriptor_set.binding_count,
        );
        errdefer allocator.free(result);

        var loaded_bindings: u32 = 0;
        errdefer {
            for (0..loaded_bindings) |i| {
                allocator.free(result[i].name);
            }
        }

        for (0..descriptor_set.binding_count) |i| {
            const binding = descriptor_set.bindings[i];

            const descriptor_type = switch (binding.*.descriptor_type) {
                c.SPV_REFLECT_DESCRIPTOR_TYPE_UNIFORM_BUFFER => gfx.DescriptorBindType.uniform,
                c.SPV_REFLECT_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => gfx.DescriptorBindType.combined_sampler,
                else => return error.UnsupportedDescriptorType,
            };

            result[i] = .{
                .name = try allocator.dupe(u8, std.mem.sliceTo(binding.*.name, 0)),
                .binding = binding.*.binding,
                .size = switch (descriptor_type) {
                    gfx.DescriptorBindType.uniform => binding.*.block.size,
                    gfx.DescriptorBindType.combined_sampler => 0,
                },
                .type = descriptor_type,
            };
            loaded_bindings += 1;

            try std_out.print("  - {s} (binding={d}, type={s}, size={s})\n", .{
                result[i].name,
                result[i].binding,
                switch (result[i].type) {
                    gfx.DescriptorBindType.uniform => "uniform",
                    gfx.DescriptorBindType.combined_sampler => "combined sampler",
                },
                std.fmt.fmtIntSizeDec(result[i].size),
            });
        }

        return result;
    }
};
