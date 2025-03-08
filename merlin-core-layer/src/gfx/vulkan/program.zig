const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Program = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    device: *const vk.Device,
    pipeline_layout: c.VkPipelineLayout,
    vertex_shader: *const vk.Shader,
    fragment_shader: *const vk.Shader,
    uniform_registry: *vk.UniformRegistry,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_layout: c.VkDescriptorSetLayout,
    descriptor_sets: [vk.MaxFramesInFlight]c.VkDescriptorSet,

    layout_names: [vk.Pipeline.MaxDescriptorSetBindings][]const u8,
    layout_types: [vk.Pipeline.MaxDescriptorSetBindings]c.VkDescriptorType,
    layout_count: u32,

    pub fn init(
        allocator: std.mem.Allocator,
        device: *const vk.Device,
        vertex_shader: *const vk.Shader,
        fragment_shader: *const vk.Shader,
        uniform_registry: *vk.UniformRegistry,
        descriptor_pool: c.VkDescriptorPool,
    ) !Self {
        var layouts: [vk.Pipeline.MaxDescriptorSetBindings]c.VkDescriptorSetLayoutBinding = undefined;
        var layout_names: [vk.Pipeline.MaxDescriptorSetBindings][]const u8 = undefined;
        var layout_sizes: [vk.Pipeline.MaxDescriptorSetBindings]u32 = undefined;
        var layout_types: [vk.Pipeline.MaxDescriptorSetBindings]c.VkDescriptorType = undefined;
        var layout_count: u32 = 0;
        errdefer {
            for (0..layout_count) |i| {
                allocator.free(layout_names[i]);
            }
        }

        for (0..vertex_shader.descriptor_set_count) |index| {
            const descriptor_set = &vertex_shader.descriptor_sets[index];

            if (descriptor_set.set != 0) {
                vk.log.err("Vertex shader descriptor set index must be 0", .{});
                return error.VertexShaderDescriptorSetIndexMustBeZero;
            }

            for (descriptor_set.bindings) |binding| {
                const layout_binding = convertDescriptorSetLayoutBinding(binding);
                layouts[layout_count] = layout_binding;
                layouts[layout_count].stageFlags |= c.VK_SHADER_STAGE_VERTEX_BIT;
                layout_names[layout_count] = try allocator.dupe(u8, binding.name);
                layout_sizes[layout_count] = binding.size;
                layout_types[layout_count] = layout_binding.descriptorType;
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
                    const layout_binding = convertDescriptorSetLayoutBinding(binding);
                    layouts[layout_count] = layout_binding;
                    layouts[layout_count].stageFlags |= c.VK_SHADER_STAGE_FRAGMENT_BIT;
                    layout_names[layout_count] = try allocator.dupe(u8, binding.name);
                    layout_sizes[layout_count] = binding.size;
                    layout_types[layout_count] = layout_binding.descriptorType;
                    layout_count += 1;
                }
            }
        }

        var descriptor_set_layout: c.VkDescriptorSetLayout = null;
        errdefer {
            if (descriptor_set_layout) |descriptor_set_layout_value| {
                device.destroyDescriptorSetLayout(descriptor_set_layout_value);
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
            };

            try device.createDescriptorSetLayout(&create_info, &descriptor_set_layout);
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
        try device.createPipelineLayout(
            &pipeline_layout_create_info,
            &pipeline_layout,
        );
        errdefer device.destroyPipelineLayout(pipeline_layout);

        var descriptor_set_layouts: [vk.MaxFramesInFlight]c.VkDescriptorSetLayout = undefined;
        for (0..vk.MaxFramesInFlight) |i| {
            descriptor_set_layouts[i] = descriptor_set_layout;
        }
        const descriptor_set_alloc_info = std.mem.zeroInit(
            c.VkDescriptorSetAllocateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
                .descriptorPool = descriptor_pool,
                .descriptorSetCount = vk.MaxFramesInFlight,
                .pSetLayouts = &descriptor_set_layouts,
            },
        );

        var descriptor_sets: [vk.MaxFramesInFlight]c.VkDescriptorSet = undefined;
        try device.allocateDescriptorSets(
            &descriptor_set_alloc_info,
            &descriptor_sets,
        );

        var created_uniforms: u32 = 0;
        errdefer {
            for (0..created_uniforms) |i| {
                if (layout_types[i] == c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
                    uniform_registry.destroy(layout_names[i]);
                }
            }
        }
        for (0..layout_count) |binding_index| {
            if (layout_types[binding_index] != c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) continue;

            const binding = layouts[binding_index];
            const name = layout_names[binding_index];
            const size = layout_sizes[binding_index];

            const entry = try uniform_registry.create(name, size);
            created_uniforms += 1;

            for (0..vk.MaxFramesInFlight) |i| {
                const buffer_info = std.mem.zeroInit(
                    c.VkDescriptorBufferInfo,
                    .{
                        .buffer = entry.buffer[i].buffer.handle,
                        .offset = 0,
                        .range = size,
                    },
                );

                const write_info = std.mem.zeroInit(
                    c.VkWriteDescriptorSet,
                    .{
                        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
                        .dstSet = descriptor_sets[i],
                        .dstBinding = binding.binding,
                        .dstArrayElement = 0,
                        .descriptorCount = 1,
                        .descriptorType = binding.descriptorType,
                        .pBufferInfo = &buffer_info,
                    },
                );

                device.updateDescriptorSets(
                    1,
                    &write_info,
                    0,
                    null,
                );
            }
        }

        return .{
            .allocator = allocator,
            .device = device,
            .pipeline_layout = pipeline_layout,
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
            .uniform_registry = uniform_registry,
            .descriptor_pool = descriptor_pool,
            .descriptor_set_layout = descriptor_set_layout,
            .descriptor_sets = descriptor_sets,
            .layout_names = layout_names,
            .layout_types = layout_types,
            .layout_count = layout_count,
        };
    }

    pub fn deinit(self: *Self) void {
        for (0..self.layout_count) |binding_index| {
            if (self.layout_types[binding_index] == c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER) {
                self.uniform_registry.destroy(self.layout_names[binding_index]);
            }
            self.allocator.free(self.layout_names[binding_index]);
        }

        self.device.freeDescriptorSets(
            self.descriptor_pool,
            vk.MaxFramesInFlight,
            &self.descriptor_sets,
        ) catch |err| {
            vk.log.err("Failed to free descriptor sets: {}", .{err});
        };

        self.device.destroyPipelineLayout(self.pipeline_layout);
        if (self.descriptor_set_layout) |descriptor_set_layout_value| {
            self.device.destroyDescriptorSetLayout(descriptor_set_layout_value);
        }
    }

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
};
