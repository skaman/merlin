const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Program = struct {
    pipeline_layout: c.VkPipelineLayout,
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,

    uniform_handles: [vk.pipeline.MaxDescriptorSetBindings]gfx.UniformHandle,
    write_descriptor_sets: [vk.pipeline.MaxDescriptorSetBindings]c.VkWriteDescriptorSet,
    descriptor_types: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorType,

    layout_count: u32,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var programs: [gfx.MaxProgramHandles]Program = undefined;
var program_handles: utils.HandlePool(gfx.ProgramHandle, gfx.MaxProgramHandles) = undefined;

var programs_to_destroy: [gfx.MaxProgramHandles]Program = undefined;
var programs_to_destroy_count: u32 = 0;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn convertBindingType(bind_type: types.DescriptorBindType) c.VkDescriptorType {
    return switch (bind_type) {
        .uniform => c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .combined_sampler => c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    };
}

fn convertDescriptorSetLayoutBinding(binding: types.DescriptorBinding) c.VkDescriptorSetLayoutBinding {
    return c.VkDescriptorSetLayoutBinding{
        .binding = binding.binding,
        .descriptorType = convertBindingType(binding.type),
        .descriptorCount = 1,
        .stageFlags = 0,
        .pImmutableSamplers = null,
    };
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    program_handles = .init();
    programs_to_destroy_count = 0;
}

pub fn deinit() void {
    program_handles.deinit();
}

pub fn create(
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
    descriptor_pool: c.VkDescriptorPool,
) !gfx.ProgramHandle {
    var layouts: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorSetLayoutBinding = undefined;
    var layout_names: [vk.pipeline.MaxDescriptorSetBindings][]const u8 = undefined;
    var layout_sizes: [vk.pipeline.MaxDescriptorSetBindings]u32 = undefined;
    var layout_count: u32 = 0;

    const vertex_shader_descriptor_sets = vk.shaders.getDescriptorSets(vertex_shader);
    for (vertex_shader_descriptor_sets) |descriptor_set| {
        if (descriptor_set.set != 0) {
            vk.log.err("Vertex shader descriptor set index must be 0", .{});
            return error.VertexShaderDescriptorSetIndexMustBeZero;
        }

        for (descriptor_set.bindings) |binding| {
            layouts[layout_count] = convertDescriptorSetLayoutBinding(binding);
            layouts[layout_count].stageFlags |= c.VK_SHADER_STAGE_VERTEX_BIT;
            layout_names[layout_count] = binding.name;
            layout_sizes[layout_count] = binding.size;
            layout_count += 1;
        }
    }

    const fragment_shader_descriptor_sets = vk.shaders.getDescriptorSets(fragment_shader);
    for (fragment_shader_descriptor_sets) |descriptor_set| {
        for (descriptor_set.bindings) |binding| {
            if (descriptor_set.set != 0) {
                vk.log.err("Fragment shader descriptor set index must be 0", .{});
                return error.VertexShaderDescriptorSetIndexMustBeZero;
            }

            var existing_descriptor_set_index: ?u32 = null;
            for (0..layout_count) |other_index| {
                const other_descriptor_set = layouts[other_index];
                if (other_descriptor_set.binding == binding.binding) {
                    existing_descriptor_set_index = @intCast(other_index);
                    if (other_descriptor_set.descriptorType != convertBindingType(binding.type)) {
                        vk.log.err("Descriptor set binding type mismatch", .{});
                        return error.DescriptorSetBindingTypeMismatch;
                    }
                    break;
                }
            }

            if (existing_descriptor_set_index) |other_index| {
                layouts[other_index].stageFlags |= c.VK_SHADER_STAGE_FRAGMENT_BIT;
            } else {
                layouts[layout_count] = convertDescriptorSetLayoutBinding(binding);
                layouts[layout_count].stageFlags |= c.VK_SHADER_STAGE_FRAGMENT_BIT;
                layout_names[layout_count] = binding.name;
                layout_sizes[layout_count] = binding.size;
                layout_count += 1;
            }
        }
    }

    var descriptor_set_layout: c.VkDescriptorSetLayout = null;
    errdefer {
        if (descriptor_set_layout) |descriptor_set_layout_value| {
            vk.device.destroyDescriptorSetLayout(descriptor_set_layout_value);
        }
    }

    if (layout_count > 0) {
        vk.log.debug("Creating descriptor set layout:", .{});
        for (0..layout_count) |binding_index| {
            const binding = layouts[binding_index];
            vk.log.debug("  - Binding {d}: type={s}, stageFlags={s}", .{
                binding.binding,
                c.string_VkDescriptorType(binding.descriptorType),
                c.string_VkShaderStageFlagBits(binding.stageFlags),
            });
        }

        const create_info = c.VkDescriptorSetLayoutCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = layout_count,
            .pBindings = &layouts,
            .flags = c.VK_DESCRIPTOR_SET_LAYOUT_CREATE_PUSH_DESCRIPTOR_BIT_KHR,
        };

        try vk.device.createDescriptorSetLayout(&create_info, &descriptor_set_layout);
    }

    const pipeline_layout_create_info = std.mem.zeroInit(
        c.VkPipelineLayoutCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptor_set_layout.?,
            .pushConstantRangeCount = 0,
            .pPushConstantRanges = null,
        },
    );

    var pipeline_layout: c.VkPipelineLayout = undefined;
    try vk.device.createPipelineLayout(
        &pipeline_layout_create_info,
        &pipeline_layout,
    );
    errdefer vk.device.destroyPipelineLayout(pipeline_layout);

    var descriptor_set_layouts: [vk.MaxFramesInFlight]c.VkDescriptorSetLayout = undefined;
    for (0..vk.MaxFramesInFlight) |i| {
        descriptor_set_layouts[i] = descriptor_set_layout;
    }

    var write_descriptor_sets: [vk.pipeline.MaxDescriptorSetBindings]c.VkWriteDescriptorSet = undefined;
    var descriptor_types: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorType = undefined;
    var uniform_handles: [vk.pipeline.MaxDescriptorSetBindings]gfx.UniformHandle = undefined;

    for (0..layout_count) |binding_index| {
        const name = layout_names[binding_index];
        const descriptor_type = layouts[binding_index].descriptorType;

        descriptor_types[binding_index] = descriptor_type;

        switch (descriptor_type) {
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                uniform_handles[binding_index] = try vk.descriptor_registry.registerName(name);
            },
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => {
                uniform_handles[binding_index] = try vk.descriptor_registry.registerName(name);
            },
            else => {
                vk.log.err(
                    "Unsupported descriptor type: {s}",
                    .{c.string_VkDescriptorType(descriptor_type)},
                );
                return error.UnsupportedDescriptorType;
            },
        }

        write_descriptor_sets[binding_index] = std.mem.zeroInit(
            c.VkWriteDescriptorSet,
            .{
                .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                .dstBinding = layouts[binding_index].binding,
                .descriptorCount = 1,
                .descriptorType = layouts[binding_index].descriptorType,
            },
        );
    }

    const handle = try program_handles.alloc();
    errdefer program_handles.free(handle);

    programs[handle] = .{
        .pipeline_layout = pipeline_layout,
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .descriptor_pool = descriptor_pool,
        .descriptor_set_layout = descriptor_set_layout,
        .uniform_handles = uniform_handles,
        .write_descriptor_sets = write_descriptor_sets,
        .descriptor_types = descriptor_types,
        .layout_count = layout_count,
    };

    vk.log.debug("Created program:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});
    vk.log.debug("  - Vertex shader handle: {d}", .{vertex_shader});
    vk.log.debug("  - Fragment shader handle: {d}", .{fragment_shader});

    return handle;
}

pub fn destroy(handle: gfx.ProgramHandle) void {
    programs_to_destroy[programs_to_destroy_count] = programs[handle];
    programs_to_destroy_count += 1;

    program_handles.free(handle);

    vk.log.debug("Destroyed program with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..programs_to_destroy_count) |i| {
        const program = &programs_to_destroy[i];
        vk.device.destroyPipelineLayout(program.pipeline_layout);
        if (program.descriptor_set_layout) |descriptor_set_layout_value| {
            vk.device.destroyDescriptorSetLayout(descriptor_set_layout_value);
        }
    }
    programs_to_destroy_count = 0;
}

pub inline fn vertexShader(handle: gfx.ProgramHandle) gfx.ShaderHandle {
    return programs[handle].vertex_shader;
}

pub inline fn fragmentShader(handle: gfx.ProgramHandle) gfx.ShaderHandle {
    return programs[handle].fragment_shader;
}

pub inline fn pipelineLayout(handle: gfx.ProgramHandle) c.VkPipelineLayout {
    return programs[handle].pipeline_layout;
}

pub inline fn layoutCount(handle: gfx.ProgramHandle) u32 {
    return programs[handle].layout_count;
}

pub inline fn writeDescriptorSets(handle: gfx.ProgramHandle) [*]c.VkWriteDescriptorSet {
    return &programs[handle].write_descriptor_sets;
}

pub inline fn uniformHandle(handle: gfx.ProgramHandle, binding_index: u32) gfx.UniformHandle {
    return programs[handle].uniform_handles[binding_index];
}

pub inline fn descriptorType(handle: gfx.ProgramHandle, binding_index: u32) c.VkDescriptorType {
    return programs[handle].descriptor_types[binding_index];
}
