const std = @import("std");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const ImageInfo = struct {
    format: c.VkFormat,
};

pub const RenderPass = struct {
    handle: c.VkRenderPass,
    color_images: []ImageInfo,
    depth_image: ?ImageInfo,
    debug_name: ?[]const u8,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _render_passes_to_destroy: std.ArrayList(*const RenderPass) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn gfxLoadOpToVulkanLoadOp(load_op: gfx.AttachmentLoadOp) c.VkAttachmentLoadOp {
    switch (load_op) {
        .clear => return c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .load => return c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .dont_care => return c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
    }
}

fn gfxStoreOpToVulkanStoreOp(store_op: gfx.AttachmentStoreOp) c.VkAttachmentStoreOp {
    switch (store_op) {
        .store => return c.VK_ATTACHMENT_STORE_OP_STORE,
        .dont_care => return c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
    }
}

fn gfxLayoutToVulkanLayout(layout: gfx.AttachmentLayout) c.VkImageLayout {
    switch (layout) {
        .undefined => return c.VK_IMAGE_LAYOUT_UNDEFINED,
        .color_attachment => return c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .depth_stencil_attachment => return c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        .present_src => return c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _render_passes_to_destroy = .init(vk.gpa);
    errdefer _render_passes_to_destroy.deinit();
}

pub fn deinit() void {
    _render_passes_to_destroy.deinit();
}

pub fn create(options: gfx.RenderPassOptions) !gfx.RenderPassHandle {
    var attachments_count = options.color_attachments.len;
    if (options.depth_attachment != null) {
        attachments_count += 1;
    }

    const attachments =
        try vk.arena.alloc(c.VkAttachmentDescription, attachments_count);
    const colors_images = try vk.gpa.alloc(ImageInfo, attachments_count);

    for (options.color_attachments, 0..) |attachment, i| {
        const color_attachment_format =
            vk.vulkanFormatFromGfxImageFormat(attachment.format);
        attachments[i] = std.mem.zeroInit(
            c.VkAttachmentDescription,
            .{
                .format = color_attachment_format,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .loadOp = gfxLoadOpToVulkanLoadOp(attachment.load_op),
                .storeOp = gfxStoreOpToVulkanStoreOp(attachment.store_op),
                .stencilLoadOp = gfxLoadOpToVulkanLoadOp(attachment.stencil_load_op),
                .stencilStoreOp = gfxStoreOpToVulkanStoreOp(attachment.stencil_store_op),
                .initialLayout = gfxLayoutToVulkanLayout(attachment.initial_layout),
                .finalLayout = gfxLayoutToVulkanLayout(attachment.final_layout),
            },
        );
        colors_images[i] = ImageInfo{
            .format = color_attachment_format,
        };
    }

    const color_attachment_ref = std.mem.zeroInit(
        c.VkAttachmentReference,
        .{
            .attachment = 0,
            .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        },
    );

    var subpass = std.mem.zeroInit(
        c.VkSubpassDescription,
        .{
            .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            .colorAttachmentCount = @as(u32, @intCast(options.color_attachments.len)),
            .pColorAttachments = &color_attachment_ref,
        },
    );

    var depth_image_info: ?ImageInfo = null;
    if (options.depth_attachment) |depth_attachment| {
        const depth_attachment_format =
            vk.vulkanFormatFromGfxImageFormat(depth_attachment.format);
        const depth_attachment_descriptor = std.mem.zeroInit(
            c.VkAttachmentDescription,
            .{
                .format = depth_attachment_format,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .loadOp = gfxLoadOpToVulkanLoadOp(depth_attachment.load_op),
                .storeOp = gfxStoreOpToVulkanStoreOp(depth_attachment.store_op),
                .stencilLoadOp = gfxLoadOpToVulkanLoadOp(depth_attachment.stencil_load_op),
                .stencilStoreOp = gfxStoreOpToVulkanStoreOp(depth_attachment.stencil_store_op),
                .initialLayout = gfxLayoutToVulkanLayout(depth_attachment.initial_layout),
                .finalLayout = gfxLayoutToVulkanLayout(depth_attachment.final_layout),
            },
        );
        attachments[attachments_count - 1] = depth_attachment_descriptor;

        const depth_attachment_ref = std.mem.zeroInit(
            c.VkAttachmentReference,
            .{
                .attachment = @as(u32, @intCast(attachments_count - 1)),
                .layout = c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            },
        );
        subpass.pDepthStencilAttachment = &depth_attachment_ref;

        depth_image_info = .{
            .format = depth_attachment_format,
        };
    }

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

    const render_pass_info = std.mem.zeroInit(
        c.VkRenderPassCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
            .attachmentCount = @as(u32, @intCast(attachments.len)),
            .pAttachments = attachments.ptr,
            .subpassCount = 1,
            .pSubpasses = &subpass,
            .dependencyCount = 1,
            .pDependencies = &dependency,
        },
    );

    var render_pass_handle: c.VkRenderPass = undefined;
    try vk.device.createRenderPass(
        &render_pass_info,
        &render_pass_handle,
    );

    const render_pass = try vk.gpa.create(RenderPass);
    errdefer vk.gpa.destroy(render_pass);

    render_pass.* = .{
        .handle = render_pass_handle,
        .color_images = colors_images,
        .depth_image = depth_image_info,
        .debug_name = null,
    };

    vk.log.debug("Created render pass:", .{});
    if (options.debug_name) |name| {
        render_pass.debug_name = try vk.gpa.dupe(u8, name);
        try vk.debug.setObjectName(c.VK_OBJECT_TYPE_RENDER_PASS, render_pass_handle, name);
        vk.log.debug("  - Name: {s}", .{name});
    }

    for (options.color_attachments, 0..) |_, i| {
        const attachment = attachments[i];
        vk.log.debug("  - Color attachment {d} format: {s}", .{ i, c.string_VkFormat(attachment.format) });
        vk.log.debug("  - Color attachment {d} samples: {s}", .{ i, c.string_VkSampleCountFlagBits(attachment.samples) });
        vk.log.debug("  - Color attachment {d} load op: {s}", .{ i, c.string_VkAttachmentLoadOp(attachment.loadOp) });
        vk.log.debug("  - Color attachment {d} store op: {s}", .{ i, c.string_VkAttachmentStoreOp(attachment.storeOp) });
        vk.log.debug("  - Color attachment {d} stencil load op: {s}", .{ i, c.string_VkAttachmentLoadOp(attachment.stencilLoadOp) });
        vk.log.debug("  - Color attachment {d} stencil store op: {s}", .{ i, c.string_VkAttachmentStoreOp(attachment.stencilStoreOp) });
        vk.log.debug("  - Color attachment {d} initial layout: {s}", .{ i, c.string_VkImageLayout(attachment.initialLayout) });
        vk.log.debug("  - Color attachment {d} final layout: {s}", .{ i, c.string_VkImageLayout(attachment.finalLayout) });
    }

    if (options.depth_attachment != null) {
        const depth_attachment = attachments[attachments_count - 1];
        vk.log.debug("  - Depth attachment format: {s}", .{c.string_VkFormat(depth_attachment.format)});
        vk.log.debug("  - Depth attachment samples: {s}", .{c.string_VkSampleCountFlagBits(depth_attachment.samples)});
        vk.log.debug("  - Depth attachment load op: {s}", .{c.string_VkAttachmentLoadOp(depth_attachment.loadOp)});
        vk.log.debug("  - Depth attachment store op: {s}", .{c.string_VkAttachmentStoreOp(depth_attachment.storeOp)});
        vk.log.debug("  - Depth attachment stencil load op: {s}", .{c.string_VkAttachmentLoadOp(depth_attachment.stencilLoadOp)});
        vk.log.debug("  - Depth attachment stencil store op: {s}", .{c.string_VkAttachmentStoreOp(depth_attachment.stencilStoreOp)});
        vk.log.debug("  - Depth attachment initial layout: {s}", .{c.string_VkImageLayout(depth_attachment.initialLayout)});
        vk.log.debug("  - Depth attachment final layout: {s}", .{c.string_VkImageLayout(depth_attachment.finalLayout)});
    }

    return .{ .handle = @ptrCast(render_pass) };
}

pub fn destroy(render_pass_handle: gfx.RenderPassHandle) void {
    const render_pass = get(render_pass_handle);
    _render_passes_to_destroy.append(render_pass) catch |err| {
        vk.log.err("Failed to append render pass to destroy list: {any}", .{err});
        return;
    };

    if (render_pass.debug_name) |name| {
        vk.log.debug("Render Pass '{s}' queued for destruction", .{name});
    }
}

pub fn destroyPendingResources() void {
    for (_render_passes_to_destroy.items) |render_pass| {
        vk.device.destroyRenderPass(render_pass.handle);
        if (render_pass.debug_name) |name| {
            vk.log.debug("Render Pass '{s}' destroyed", .{name});
            vk.gpa.free(name);
        }
        vk.gpa.free(render_pass.color_images);
        vk.gpa.destroy(render_pass);
    }
    _render_passes_to_destroy.clearRetainingCapacity();
}

pub fn get(render_pass: gfx.RenderPassHandle) *const RenderPass {
    return @ptrCast(@alignCast(render_pass.handle));
}
