const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const RenderPass = struct {
    const Self = @This();

    handle: c.VkRenderPass,
    device: *const vk.Device,

    pub fn init(device: *const vk.Device, format: c.VkFormat) !Self {
        const color_attachment = std.mem.zeroInit(
            c.VkAttachmentDescription,
            .{
                .format = format,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            },
        );

        const color_attachment_ref = std.mem.zeroInit(
            c.VkAttachmentReference,
            .{
                .attachment = 0,
                .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            },
        );

        const subpass = std.mem.zeroInit(
            c.VkSubpassDescription,
            .{
                .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                .colorAttachmentCount = 1,
                .pColorAttachments = &color_attachment_ref,
            },
        );

        const dependency = std.mem.zeroInit(
            c.VkSubpassDependency,
            .{
                .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                .dstSubpass = 0,
                .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .srcAccessMask = 0,
                .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            },
        );

        const render_pass_info = std.mem.zeroInit(
            c.VkRenderPassCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                .attachmentCount = 1,
                .pAttachments = &color_attachment,
                .subpassCount = 1,
                .pSubpasses = &subpass,
                .dependencyCount = 1,
                .pDependencies = &dependency,
            },
        );

        var render_pass: c.VkRenderPass = undefined;
        try device.createRenderPass(
            &render_pass_info,
            &render_pass,
        );
        return .{
            .handle = render_pass,
            .device = device,
        };
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyRenderPass(self.handle);
    }
};
