const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Program = struct {
    const Self = @This();

    device: *const vk.Device,
    pipeline_layout: c.VkPipelineLayout,
    vertex_shader: *const vk.Shader,
    fragment_shader: *const vk.Shader,

    pub fn init(
        device: *const vk.Device,
        vertex_shader: *const vk.Shader,
        fragment_shader: *const vk.Shader,
    ) !Self {
        const pipeline_layout_create_info = std.mem.zeroInit(
            c.VkPipelineLayoutCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .setLayoutCount = 0,
                .pSetLayouts = null,
                .pushConstantRangeCount = 0,
                .pPushConstantRanges = null,
            },
        );

        var pipeline_layout: c.VkPipelineLayout = undefined;
        try device.createPipelineLayout(
            &pipeline_layout_create_info,
            &pipeline_layout,
        );
        return .{
            .device = device,
            .pipeline_layout = pipeline_layout,
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyPipelineLayout(self.pipeline_layout);
    }
};
