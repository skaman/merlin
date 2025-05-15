const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Shader = struct {
    module: c.VkShaderModule,
    input_attributes: []const types.ShaderInputAttribute,
    descriptor_sets: []const types.DescriptorSet,
    push_constants: []const types.PushConstant,
    debug_name: ?[]const u8,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _shaders_to_destroy: std.ArrayList(*Shader) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn dupeShaderInputAttributes(input_attributes: []const types.ShaderInputAttribute) ![]const types.ShaderInputAttribute {
    var duped = try vk.gpa.alloc(types.ShaderInputAttribute, input_attributes.len);
    for (input_attributes, 0..) |input_attribute, i| {
        duped[i] = input_attribute;
    }
    return duped;
}

fn dupeDescriptorSets(descriptor_sets: []const types.DescriptorSet) ![]const types.DescriptorSet {
    var duped = try vk.gpa.alloc(types.DescriptorSet, descriptor_sets.len);
    for (descriptor_sets, 0..) |descriptor_set, i| {
        duped[i] = descriptor_set;
        var bindings = try vk.gpa.dupe(types.DescriptorBinding, descriptor_set.bindings);
        for (descriptor_set.bindings, 0..) |binding, j| {
            bindings[j].name = try vk.gpa.dupe(u8, binding.name);
        }
        duped[i].bindings = bindings;
    }
    return duped;
}

fn dupePushConstants(push_constants: []const types.PushConstant) ![]const types.PushConstant {
    var duped = try vk.gpa.alloc(types.PushConstant, push_constants.len);
    for (push_constants, 0..) |push_constant, i| {
        duped[i] = push_constant;
        duped[i].name = try vk.gpa.dupe(u8, push_constant.name);
    }
    return duped;
}

fn freeShaderInputAttributes(input_attributes: []const types.ShaderInputAttribute) void {
    vk.gpa.free(input_attributes);
}

fn freeDescriptorSets(descriptor_sets: []const types.DescriptorSet) void {
    for (descriptor_sets) |descriptor_set| {
        for (descriptor_set.bindings) |binding| {
            vk.gpa.free(binding.name);
        }
        vk.gpa.free(descriptor_set.bindings);
    }
    vk.gpa.free(descriptor_sets);
}

fn freePushConstants(push_constants: []const types.PushConstant) void {
    for (push_constants) |push_constant| {
        vk.gpa.free(push_constant.name);
    }
    vk.gpa.free(push_constants);
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _shaders_to_destroy = .init(vk.gpa);
    errdefer _shaders_to_destroy.deinit();
}

pub fn deinit() void {
    _shaders_to_destroy.deinit();
}

pub fn create(reader: std.io.AnyReader, options: gfx.ShaderOptions) !gfx.ShaderHandle {
    try utils.Serializer.checkHeader(reader, types.ShaderMagic, types.ShaderVersion);
    const data = try utils.Serializer.read(
        types.ShaderData,
        vk.arena,
        reader,
    );

    var module: c.VkShaderModule = undefined;
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = data.data.len,
        .pCode = @ptrCast(data.data.ptr),
    };
    try vk.device.createShaderModule(&create_info, &module);

    const shader = try vk.gpa.create(Shader);
    errdefer vk.gpa.destroy(shader);

    const input_attributes = try dupeShaderInputAttributes(data.input_attributes);
    errdefer freeShaderInputAttributes(input_attributes);

    const descriptor_sets = try dupeDescriptorSets(data.descriptor_sets);
    errdefer freeDescriptorSets(descriptor_sets);

    const push_constants = try dupePushConstants(data.push_constants);
    errdefer freePushConstants(push_constants);

    shader.* = .{
        .module = module,
        .input_attributes = input_attributes,
        .descriptor_sets = descriptor_sets,
        .push_constants = push_constants,
        .debug_name = null,
    };

    vk.log.debug("Created {s} shader:", .{switch (data.type) {
        .vertex => "vertex",
        .fragment => "fragment",
    }});

    if (options.debug_name) |name| {
        shader.debug_name = try vk.gpa.dupe(u8, name);
        try vk.debug.setObjectName(c.VK_OBJECT_TYPE_SHADER_MODULE, module, name);
        vk.log.debug("  - Name: {s}", .{name});
    }

    for (data.input_attributes) |input_attribute| {
        vk.log.debug("  - Attribute {d}: {s}", .{ input_attribute.location, input_attribute.attribute.name() });
    }

    for (data.descriptor_sets) |descriptor_set| {
        vk.log.debug("  - Descriptor set {d}:", .{descriptor_set.set});
        for (descriptor_set.bindings) |binding| {
            vk.log.debug("    Binding {d}: {s} {s}", .{ binding.binding, binding.name, binding.type.name() });
        }
    }

    for (data.push_constants) |push_constant| {
        vk.log.debug("  - Push constant: {s} ({d} bytes)", .{ push_constant.name, push_constant.size });
    }

    return .{ .handle = @ptrCast(shader) };
}

pub fn destroy(handle: gfx.ShaderHandle) void {
    const shader = get(handle);
    _shaders_to_destroy.append(shader) catch |err| {
        vk.log.err("Failed to append shader to destroy list: {any}", .{err});
        return;
    };

    if (shader.debug_name) |name| {
        vk.log.debug("Shader '{s}' queued for destruction", .{name});
    }
}

pub fn destroyPendingResources() void {
    for (_shaders_to_destroy.items) |shader| {
        vk.device.destroyShaderModule(shader.module);
        if (shader.debug_name) |name| {
            vk.log.debug("Shader '{s}' destroyed", .{name});
            vk.gpa.free(name);
        }
        freeShaderInputAttributes(shader.input_attributes);
        freeDescriptorSets(shader.descriptor_sets);
        freePushConstants(shader.push_constants);
        vk.gpa.destroy(shader);
    }
    _shaders_to_destroy.clearRetainingCapacity();
}

pub inline fn get(handle: gfx.ShaderHandle) *Shader {
    return @ptrCast(@alignCast(handle.handle));
}
