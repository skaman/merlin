const std = @import("std");

const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;

const c = @import("c.zig").c;

// *********************************************************************************************
// Constants
// *********************************************************************************************

const AttributeMapEntry = struct {
    name: []const u8,
    attribute: gfx_types.VertexAttributeType,
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

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn parseDescriptorSet(
    allocator: std.mem.Allocator,
    descriptor_set: *c.SpvReflectDescriptorSet,
    //std_out: anytype,
) ![]gfx_types.DescriptorBinding {
    const result = try allocator.alloc(
        gfx_types.DescriptorBinding,
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
            c.SPV_REFLECT_DESCRIPTOR_TYPE_UNIFORM_BUFFER => gfx_types.DescriptorBindType.uniform_buffer,
            c.SPV_REFLECT_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => gfx_types.DescriptorBindType.combined_sampler,
            else => return error.UnsupportedDescriptorType,
        };

        result[i] = .{
            .name = try allocator.dupe(u8, std.mem.sliceTo(binding.*.name, 0)),
            .binding = binding.*.binding,
            .size = switch (descriptor_type) {
                gfx_types.DescriptorBindType.uniform_buffer => binding.*.block.size,
                gfx_types.DescriptorBindType.combined_sampler => 0,
            },
            .type = descriptor_type,
        };
        loaded_bindings += 1;
    }

    return result;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub const DescriptorSets = struct {
    allocator: std.mem.Allocator,
    sets: []gfx_types.DescriptorSet,

    pub fn deinit(self: *const DescriptorSets) void {
        for (self.sets) |descriptor_set| {
            for (descriptor_set.bindings) |binding| {
                self.allocator.free(binding.name);
            }
            self.allocator.free(descriptor_set.bindings);
        }
        self.allocator.free(self.sets);
    }
};

pub const InputAttributes = struct {
    allocator: std.mem.Allocator,
    attributes: []gfx_types.ShaderInputAttribute,
    input_variables: []InputVariable,

    pub fn deinit(self: *const InputAttributes) void {
        self.allocator.free(self.attributes);

        for (self.input_variables) |input_variable| {
            input_variable.deinit();
        }
        self.allocator.free(self.input_variables);
    }
};

pub const InputVariable = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    location: u32,

    pub fn deinit(self: *const InputVariable) void {
        self.allocator.free(self.name);
    }
};

pub const PushConstants = struct {
    allocator: std.mem.Allocator,
    items: []gfx_types.PushConstant,

    pub fn deinit(self: *const PushConstants) void {
        for (self.items) |push_constant| {
            self.allocator.free(push_constant.name);
        }
        self.allocator.free(self.items);
    }
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

    pub fn inputAttributes(
        self: *ShaderReflect,
        allocator: std.mem.Allocator,
    ) !InputAttributes {
        var input_variable_count: u32 = 0;
        if (c.spvReflectEnumerateInputVariables(
            &self.shader_module,
            &input_variable_count,
            null,
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate input variables", .{});
            return error.FailedEnumerateInputVariables;
        }

        const spv_input_variables = try allocator.alloc(
            *c.SpvReflectInterfaceVariable,
            input_variable_count,
        );
        defer allocator.free(spv_input_variables);

        var input_variables = try allocator.alloc(
            InputVariable,
            input_variable_count,
        );

        if (c.spvReflectEnumerateInputVariables(
            &self.shader_module,
            &input_variable_count,
            @ptrCast(spv_input_variables.ptr),
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate input variables", .{});
            return error.FailedEnumerateInputVariables;
        }

        const result = try allocator.alloc(
            gfx_types.ShaderInputAttribute,
            input_variable_count,
        );
        errdefer allocator.free(result);

        for (spv_input_variables, 0..) |input, i| {
            input_variables[i] = .{
                .allocator = allocator,
                .name = try allocator.dupe(u8, std.mem.sliceTo(input.name, 0)),
                .location = input.location,
            };
            var attribute: ?gfx_types.VertexAttributeType = null;
            for (AttributeMap) |entry| {
                if (std.mem.eql(
                    u8,
                    std.mem.sliceTo(input.name, 0),
                    entry.name,
                )) {
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
                .location = @intCast(input.location),
            };
        }

        return .{
            .allocator = allocator,
            .attributes = result,
            .input_variables = input_variables,
        };
    }

    pub fn descriptorSets(
        self: *ShaderReflect,
        allocator: std.mem.Allocator,
        //std_out: anytype,
    ) !DescriptorSets {
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
            gfx_types.DescriptorSet,
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
            //try std_out.print("Descriptor set {d}:\n", .{descriptor_set.set});

            result[i].set = descriptor_set.set;
            result[i].bindings = try parseDescriptorSet(allocator, descriptor_set);
            loaded_descriptor_sets += 1;
        }

        return .{
            .allocator = allocator,
            .sets = result,
        };
    }

    pub fn pushConstants(
        self: *ShaderReflect,
        allocator: std.mem.Allocator,
    ) !PushConstants {
        var push_constants_count: u32 = 0;
        if (c.spvReflectEnumeratePushConstants(
            &self.shader_module,
            &push_constants_count,
            null,
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate push constants", .{});
            return error.FailedEnumerateDescriptorSets;
        }

        const push_constants = try allocator.alloc(
            *c.SpvReflectBlockVariable,
            push_constants_count,
        );
        defer allocator.free(push_constants);

        if (c.spvReflectEnumeratePushConstants(
            &self.shader_module,
            &push_constants_count,
            @ptrCast(push_constants.ptr),
        ) != c.SPV_REFLECT_RESULT_SUCCESS) {
            std.log.err("Failed to enumerate push constants", .{});
            return error.FailedEnumerateDescriptorSets;
        }

        const items = try allocator.alloc(
            gfx_types.PushConstant,
            push_constants_count,
        );
        errdefer allocator.free(items);

        for (push_constants, 0..) |push_constant, i| {
            items[i] = .{
                .name = try allocator.dupe(u8, std.mem.sliceTo(push_constant.name, 0)),
                .offset = push_constant.offset,
                .size = push_constant.size,
            };
        }

        return .{
            .allocator = allocator,
            .items = items,
        };
    }
};
