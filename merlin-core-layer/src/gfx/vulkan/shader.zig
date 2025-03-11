const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Shader = struct {
    const Self = @This();

    handle: c.VkShaderModule,
    input_attributes: [vk.Pipeline.MaxVertexAttributes]gfx.ShaderInputAttribute,
    input_attribute_count: u8,
    descriptor_sets: [vk.Pipeline.MaxDescriptorSetBindings]gfx.DescriptorSet,
    descriptor_set_count: u8,

    pub fn init(data: *const gfx.ShaderData) !Self {
        if (data.input_attributes.len > vk.Pipeline.MaxVertexAttributes) {
            vk.log.err("Input attributes count exceeds maximum vertex attributes", .{});
            return error.MaxVertexAttributesExceeded;
        }

        if (data.descriptor_sets.len > vk.Pipeline.MaxDescriptorSetBindings) {
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

        var self = Self{
            .handle = module,
            .input_attributes = undefined,
            .input_attribute_count = @intCast(data.input_attributes.len),
            .descriptor_sets = undefined,
            .descriptor_set_count = @intCast(data.descriptor_sets.len),
        };

        @memcpy(self.input_attributes[0..data.input_attributes.len], data.input_attributes);
        @memcpy(self.descriptor_sets[0..data.descriptor_sets.len], data.descriptor_sets);

        return self;
    }

    pub fn deinit(self: *Self) void {
        vk.device.destroyShaderModule(self.handle);
    }
};
