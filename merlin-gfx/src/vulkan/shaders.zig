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
    input_attributes: [vk.pipeline.MaxVertexAttributes]types.ShaderInputAttribute,
    input_attribute_count: u8,
    descriptor_sets: [vk.pipeline.MaxDescriptorSetBindings]types.DescriptorSet,
    descriptor_set_count: u8,
    debug_name: ?[]const u8 = null,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _shaders_to_destroy: std.ArrayList(*Shader) = undefined;

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

    if (data.input_attributes.len > vk.pipeline.MaxVertexAttributes) {
        vk.log.err("Input attributes count exceeds maximum vertex attributes", .{});
        return error.MaxVertexAttributesExceeded;
    }

    if (data.descriptor_sets.len > vk.pipeline.MaxDescriptorSetBindings) {
        vk.log.err("Descriptor sets count exceeds maximum descriptor sets", .{});
        return error.MaxDescriptorSetsExceeded;
    }

    var module: c.VkShaderModule = undefined;
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = data.data.len,
        .pCode = @ptrCast(data.data.ptr),
    };
    try vk.device.createShaderModule(&create_info, &module);

    const shader = try vk.gpa.create(Shader);
    errdefer vk.gpa.destroy(shader);

    shader.* = .{
        .module = module,
        .input_attributes = undefined,
        .input_attribute_count = @intCast(data.input_attributes.len),
        .descriptor_sets = undefined,
        .descriptor_set_count = @intCast(data.descriptor_sets.len),
        .debug_name = null,
    };

    @memcpy(shader.input_attributes[0..data.input_attributes.len], data.input_attributes);
    @memcpy(shader.descriptor_sets[0..data.descriptor_sets.len], data.descriptor_sets);

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

    return .{ .handle = @ptrCast(shader) };
}

pub fn destroy(handle: gfx.ShaderHandle) void {
    const shader = shaderFromHandle(handle);
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
        vk.gpa.destroy(shader);
    }
    _shaders_to_destroy.clearRetainingCapacity();
}

pub inline fn shaderFromHandle(handle: gfx.ShaderHandle) *Shader {
    return @ptrCast(@alignCast(handle.handle));
}
