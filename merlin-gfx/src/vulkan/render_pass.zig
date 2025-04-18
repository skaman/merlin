const std = @import("std");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn create(format: c.VkFormat) !c.VkRenderPass {
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

    const depth_attachment = std.mem.zeroInit(
        c.VkAttachmentDescription,
        .{
            .format = try vk.depth_image.findDepthFormat(),
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        },
    );

    const color_attachment_ref = std.mem.zeroInit(
        c.VkAttachmentReference,
        .{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        },
    );

    const depth_attachment_ref = std.mem.zeroInit(
        c.VkAttachmentReference,
        .{
            .attachment = 1,
            .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        },
    );

    const subpass = std.mem.zeroInit(
        c.VkSubpassDescription,
        .{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color_attachment_ref,
            .pDepthStencilAttachment = &depth_attachment_ref,
        },
    );

    const dependency = std.mem.zeroInit(
        c.VkSubpassDependency,
        .{
            .srcSubpass = c.VK_SUBPASS_EXTERNAL,
            .dstSubpass = 0,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                c.VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        },
    );

    const attachments = [_]c.VkAttachmentDescription{ color_attachment, depth_attachment };

    const render_pass_info = std.mem.zeroInit(
        c.VkRenderPassCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &dependency,
        },
    );

    var render_pass: c.VkRenderPass = undefined;
    try vk.device.createRenderPass(
        &render_pass_info,
        &render_pass,
    );
    return render_pass;
}

pub fn destroy(render_pass: c.VkRenderPass) void {
    vk.device.destroyRenderPass(render_pass);
}
