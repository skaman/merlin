const std = @import("std");

const shared = @import("shared");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Shader = struct {
    const Self = @This();

    device: *const vk.Device,
    handle: c.VkShaderModule,
    input_attribute_count: u8,
    input_attributes: [vk.Pipeline.MaxVertexAttributes]?shared.Attribute,

    pub fn init(
        device: *const vk.Device,
        data: *const shared.ShaderData,
    ) !Self {
        var handle: c.VkShaderModule = undefined;
        const create_info = c.VkShaderModuleCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
            .codeSize = data.data.len,
            .pCode = @ptrCast(data.data.ptr),
        };
        try device.createShaderModule(&create_info, &handle);

        var self = Self{
            .device = device,
            .handle = handle,
            .input_attribute_count = @intCast(data.input_attributes.len),
            .input_attributes = undefined,
        };

        @memcpy(self.input_attributes[0..data.input_attributes.len], data.input_attributes);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyShaderModule(self.handle);
    }
};
