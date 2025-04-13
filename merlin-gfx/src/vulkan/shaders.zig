const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Shader = struct {
    handle: c.VkShaderModule,
    input_attributes: [vk.pipeline.MaxVertexAttributes]types.ShaderInputAttribute,
    input_attribute_count: u8,
    descriptor_sets: [vk.pipeline.MaxDescriptorSetBindings]types.DescriptorSet,
    descriptor_set_count: u8,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var shaders: utils.HandleArray(
    gfx.ShaderHandle,
    Shader,
    gfx.MaxShaderHandles,
) = undefined;

var shader_handles: utils.HandlePool(
    gfx.ShaderHandle,
    gfx.MaxShaderHandles,
) = undefined;

var shaders_to_destroy: [gfx.MaxShaderHandles]Shader = undefined;
var shaders_to_destroy_count: u32 = 0;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    shader_handles = .init();
    shaders_to_destroy_count = 0;
}

pub fn deinit() void {
    shader_handles.deinit();
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

    const handle = shader_handles.create();
    errdefer shader_handles.destroy(handle);

    shaders.setValue(
        handle,
        .{
            .handle = module,
            .input_attributes = undefined,
            .input_attribute_count = @intCast(data.input_attributes.len),
            .descriptor_sets = undefined,
            .descriptor_set_count = @intCast(data.descriptor_sets.len),
        },
    );

    const shader = shaders.valuePtr(handle);
    @memcpy(shader.input_attributes[0..data.input_attributes.len], data.input_attributes);
    @memcpy(shader.descriptor_sets[0..data.descriptor_sets.len], data.descriptor_sets);

    vk.log.debug("Created {s} shader:", .{switch (data.type) {
        .vertex => "vertex",
        .fragment => "fragment",
    }});
    vk.log.debug("  - Handle: {d}", .{handle});
    if (options.debug_name) |name| {
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

    return handle;
}

pub fn destroy(handle: gfx.ShaderHandle) void {
    shaders_to_destroy[shaders_to_destroy_count] = shaders.value(handle);
    shaders_to_destroy_count += 1;

    shader_handles.destroy(handle);

    vk.log.debug("Destroyed shader with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..shaders_to_destroy_count) |i| {
        vk.device.destroyShaderModule(shaders_to_destroy[i].handle);
    }
    shaders_to_destroy_count = 0;
}

pub inline fn getShaderModule(handle: gfx.ShaderHandle) c.VkShaderModule {
    const shader = shaders.valuePtr(handle);
    return shader.handle;
}

pub inline fn getInputAttributes(handle: gfx.ShaderHandle) []types.ShaderInputAttribute {
    const shader = shaders.valuePtr(handle);
    return shader.input_attributes[0..shader.input_attribute_count];
}

pub inline fn getDescriptorSets(handle: gfx.ShaderHandle) []types.DescriptorSet {
    const shader = shaders.valuePtr(handle);
    return shader.descriptor_sets[0..shader.descriptor_set_count];
}
