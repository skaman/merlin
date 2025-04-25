const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Program = struct {
    pipeline_layout: c.VkPipelineLayout,
    vertex_shader: *vk.shaders.Shader,
    fragment_shader: *vk.shaders.Shader,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,

    uniform_name_handles: [vk.pipeline.MaxDescriptorSetBindings]gfx.NameHandle,
    write_descriptor_sets: [vk.pipeline.MaxDescriptorSetBindings]c.VkWriteDescriptorSet,
    descriptor_types: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorType,
    uniform_sizes: [vk.pipeline.MaxDescriptorSetBindings]u32,

    layout_count: u32,

    debug_name: ?[]const u8,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _programs_to_destroy: std.ArrayList(*Program) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn convertBindingType(bind_type: types.DescriptorBindType) c.VkDescriptorType {
    return switch (bind_type) {
        .uniform_buffer => c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
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
    _programs_to_destroy = .init(vk.gpa);
    errdefer _programs_to_destroy.deinit();
}

pub fn deinit() void {
    _programs_to_destroy.deinit();
}

pub fn create(
    vertex_shader_handle: gfx.ShaderHandle,
    fragment_shader_handle: gfx.ShaderHandle,
    descriptor_pool: c.VkDescriptorPool,
    options: gfx.ProgramOptions,
) !gfx.ProgramHandle {
    var layouts: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorSetLayoutBinding = undefined;
    var layout_names: [vk.pipeline.MaxDescriptorSetBindings][]const u8 = undefined;
    var layout_sizes: [vk.pipeline.MaxDescriptorSetBindings]u32 = undefined;
    var layout_count: u32 = 0;

    const vertex_shader = vk.shaders.shaderFromHandle(vertex_shader_handle);
    const fragment_shader = vk.shaders.shaderFromHandle(fragment_shader_handle);

    for (vertex_shader.descriptor_sets) |descriptor_set| {
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

    for (fragment_shader.descriptor_sets) |descriptor_set| {
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

    var push_constants: [vk.pipeline.MaxPushConstants]c.VkPushConstantRange = undefined;
    var push_constant_count: u32 = 0;

    for (vertex_shader.push_constants) |push_constant| {
        push_constants[push_constant_count] = c.VkPushConstantRange{
            .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT,
            .offset = push_constant.offset,
            .size = push_constant.size,
        };
        push_constant_count += 1;
    }

    for (fragment_shader.push_constants) |push_constant| {
        push_constants[push_constant_count] = c.VkPushConstantRange{
            .stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .offset = push_constant.offset,
            .size = push_constant.size,
        };
        push_constant_count += 1;
    }

    const pipeline_layout_create_info = std.mem.zeroInit(
        c.VkPipelineLayoutCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &descriptor_set_layout.?,
            .pushConstantRangeCount = push_constant_count,
            .pPushConstantRanges = &push_constants,
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
    var uniform_sizes: [vk.pipeline.MaxDescriptorSetBindings]u32 = undefined;
    var uniform_name_handles: [vk.pipeline.MaxDescriptorSetBindings]gfx.NameHandle = undefined;

    for (0..layout_count) |binding_index| {
        const name = layout_names[binding_index];
        const descriptor_type = layouts[binding_index].descriptorType;
        const size = layout_sizes[binding_index];

        descriptor_types[binding_index] = descriptor_type;
        uniform_sizes[binding_index] = size;
        uniform_name_handles[binding_index] = gfx.nameHandle(name);

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

    const program = try vk.gpa.create(Program);
    errdefer vk.gpa.destroy(program);
    program.* = .{
        .pipeline_layout = pipeline_layout,
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .descriptor_pool = descriptor_pool,
        .descriptor_set_layout = descriptor_set_layout,
        .uniform_name_handles = uniform_name_handles,
        .write_descriptor_sets = write_descriptor_sets,
        .descriptor_types = descriptor_types,
        .uniform_sizes = uniform_sizes,
        .layout_count = layout_count,
        .debug_name = null,
    };

    vk.log.debug("Created program:", .{});
    if (options.debug_name) |name| {
        program.debug_name = try vk.gpa.dupe(u8, name);
        vk.log.debug("  - Name: {s}", .{name});
    }
    if (vertex_shader.debug_name) |name| {
        vk.log.debug("  - Vertex shader name: {s}", .{name});
    }
    if (fragment_shader.debug_name) |name| {
        vk.log.debug("  - Fragment shader name: {s}", .{name});
    }

    return .{ .handle = @ptrCast(program) };
}

pub fn destroy(handle: gfx.ProgramHandle) void {
    const program = programFromHandle(handle);
    _programs_to_destroy.append(program) catch |err| {
        vk.log.err("Failed to append program to destroy list: {any}", .{err});
        return;
    };

    if (program.debug_name) |name| {
        vk.log.debug("Program '{s}' queued for destruction", .{name});
    }
}

pub fn destroyPendingResources() void {
    for (_programs_to_destroy.items) |program| {
        vk.device.destroyPipelineLayout(program.pipeline_layout);
        if (program.descriptor_set_layout) |descriptor_set_layout_value| {
            vk.device.destroyDescriptorSetLayout(descriptor_set_layout_value);
        }
        if (program.debug_name) |name| {
            vk.log.debug("Program '{s}' destroyed", .{name});
            vk.gpa.free(name);
        }
        vk.gpa.destroy(program);
    }
    _programs_to_destroy.clearRetainingCapacity();
}

pub inline fn programFromHandle(handle: gfx.ProgramHandle) *Program {
    return @ptrCast(@alignCast(handle.handle));
}
