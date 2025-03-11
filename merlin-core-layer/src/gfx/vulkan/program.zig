const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

fn convertBindingType(bind_type: gfx.DescriptorBindType) c.VkDescriptorType {
    return switch (bind_type) {
        .uniform => c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .combined_sampler => c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    };
}

fn convertDescriptorSetLayoutBinding(binding: gfx.DescriptorBinding) c.VkDescriptorSetLayoutBinding {
    return c.VkDescriptorSetLayoutBinding{
        .binding = binding.binding,
        .descriptorType = convertBindingType(binding.type),
        .descriptorCount = 1,
        .stageFlags = 0,
        .pImmutableSamplers = null,
    };
}

pub const Program = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    pipeline_layout: c.VkPipelineLayout,
    vertex_shader: *const vk.Shader,
    fragment_shader: *const vk.Shader,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,

    uniform_handles: [vk.Pipeline.MaxDescriptorSetBindings]gfx.UniformHandle,
    write_descriptor_sets: [vk.Pipeline.MaxDescriptorSetBindings]c.VkWriteDescriptorSet,
    descriptor_types: [vk.Pipeline.MaxDescriptorSetBindings]c.VkDescriptorType,

    layout_count: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        vertex_shader: *const vk.Shader,
        fragment_shader: *const vk.Shader,
        descriptor_pool: c.VkDescriptorPool,
    ) !Self {
        var layouts: [vk.Pipeline.MaxDescriptorSetBindings]c.VkDescriptorSetLayoutBinding = undefined;
        var layout_names: [vk.Pipeline.MaxDescriptorSetBindings][]const u8 = undefined;
        var layout_sizes: [vk.Pipeline.MaxDescriptorSetBindings]u32 = undefined;
        var layout_count: u32 = 0;

        for (0..vertex_shader.descriptor_set_count) |index| {
            const descriptor_set = &vertex_shader.descriptor_sets[index];

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

        for (0..fragment_shader.descriptor_set_count) |index| {
            const descriptor_set = &fragment_shader.descriptor_sets[index];
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

        var write_descriptor_sets: [vk.Pipeline.MaxDescriptorSetBindings]c.VkWriteDescriptorSet = undefined;
        var descriptor_types: [vk.Pipeline.MaxDescriptorSetBindings]c.VkDescriptorType = undefined;
        var uniform_handles: [vk.Pipeline.MaxDescriptorSetBindings]gfx.UniformHandle = undefined;
        errdefer {
            for (0..layout_count) |binding_index| {
                vk.uniform_registry.destroy(uniform_handles[binding_index]);
            }
        }

        for (0..layout_count) |binding_index| {
            const name = layout_names[binding_index];
            const size = layout_sizes[binding_index];
            const descriptor_type = layouts[binding_index].descriptorType;

            descriptor_types[binding_index] = descriptor_type;

            switch (descriptor_type) {
                c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                    uniform_handles[binding_index] = try vk.uniform_registry.createBuffer(name, size);
                },
                c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => {
                    uniform_handles[binding_index] = try vk.uniform_registry.createCombinedSampler(name);
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

        return .{
            .allocator = allocator,
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
    }

    pub fn deinit(self: *Self) void {
        for (0..self.layout_count) |binding_index| {
            vk.uniform_registry.destroy(self.uniform_handles[binding_index]);
        }

        vk.device.destroyPipelineLayout(self.pipeline_layout);
        if (self.descriptor_set_layout) |descriptor_set_layout_value| {
            vk.device.destroyDescriptorSetLayout(descriptor_set_layout_value);
        }
    }

    pub fn pushDescriptorSet(
        self: *Self,
        command_buffers: *const vk.command_buffers.CommandBuffers,
        index: u32,
        textures: []vk.Texture,
    ) !void {
        for (0..self.layout_count) |binding_index| {
            const handle = self.uniform_handles[binding_index];
            switch (self.descriptor_types[binding_index]) {
                c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                    self.write_descriptor_sets[binding_index].pBufferInfo = &.{
                        .buffer = vk.uniform_registry.getBuffer(handle, index),
                        .offset = 0,
                        .range = vk.uniform_registry.getBufferSize(handle),
                    };
                },
                c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => {
                    const texture_handle = vk.uniform_registry.getCombinedSamplerTexture(handle);
                    if (texture_handle) |texture_handle_value| {
                        const texture = &textures[texture_handle_value];
                        self.write_descriptor_sets[binding_index].pImageInfo = &.{
                            .imageLayout = texture.ktx_texture.imageLayout,
                            .imageView = texture.image_view,
                            .sampler = texture.sampler,
                        };
                    } else {
                        vk.log.err("Texture handle is null for descriptor {d}", .{binding_index});
                        return error.TextureHandleIsNull;
                    }
                },
                else => {
                    vk.log.err(
                        "Unsupported descriptor type: {s}",
                        .{c.string_VkDescriptorType(self.descriptor_types[binding_index])},
                    );
                    return error.UnsupportedDescriptorType;
                },
            }
        }

        command_buffers.pushDescriptorSet(
            index,
            self.pipeline_layout,
            0,
            self.layout_count,
            &self.write_descriptor_sets,
        );
    }
};
