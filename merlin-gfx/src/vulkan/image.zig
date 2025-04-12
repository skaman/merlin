const std = @import("std");

const platform = @import("../../platform/platform.zig");
const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Image = struct {
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    size: u64,
};

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn create(
    width: u32,
    height: u32,
    depth: u32,
    format: c.VkFormat,
    mip_levels: u32,
    array_layers: u32,
    tiling: c.VkImageTiling,
    usage: c.VkImageUsageFlags,
    initial_layout: c.VkImageLayout,
    properties: c.VkMemoryPropertyFlags,
) !Image {
    const image_info = std.mem.zeroInit(
        c.VkImageCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .imageType = c.VK_IMAGE_TYPE_2D,
            .extent = .{
                .width = width,
                .height = height,
                .depth = depth,
            },
            .mipLevels = mip_levels,
            .arrayLayers = array_layers,
            .format = format,
            .tiling = tiling,
            .initialLayout = initial_layout,
            .usage = usage,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        },
    );

    var image: c.VkImage = undefined;
    try vk.device.createImage(&image_info, &image);
    errdefer vk.device.destroyImage(image);

    var memory_requirements: c.VkMemoryRequirements = undefined;
    vk.device.getImageMemoryRequirements(
        image,
        &memory_requirements,
    );

    const memory_type_index = try vk.findMemoryTypeIndex(
        memory_requirements.memoryTypeBits,
        properties,
    );

    const alloc_info = std.mem.zeroInit(
        c.VkMemoryAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
            .allocationSize = memory_requirements.size,
            .memoryTypeIndex = memory_type_index,
        },
    );

    var memory: c.VkDeviceMemory = undefined;
    try vk.device.allocateMemory(&alloc_info, &memory);
    errdefer vk.device.freeMemory(memory);

    try vk.device.bindImageMemory(image, memory, 0);

    return .{
        .image = image,
        .memory = memory,
        .size = memory_requirements.size,
    };
}

pub fn destroy(image: Image) void {
    vk.device.destroyImage(image.image);
    vk.device.freeMemory(image.memory);
}

pub fn createView(
    image: c.VkImage,
    format: c.VkFormat,
    view_type: c.VkImageViewType,
    aspect_flags: c.VkImageAspectFlags,
    level_count: u32,
    layer_count: u32,
) !c.VkImageView {
    const view_info = std.mem.zeroInit(
        c.VkImageViewCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = view_type,
            .format = format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = aspect_flags,
                .baseMipLevel = 0,
                .levelCount = level_count,
                .baseArrayLayer = 0,
                .layerCount = layer_count,
            },
        },
    );

    var view: c.VkImageView = undefined;
    try vk.device.createImageView(&view_info, &view);
    return view;
}

pub fn destroyView(view: c.VkImageView) void {
    vk.device.destroyImageView(view);
}

pub fn setImageLayout(
    command_buffer: c.VkCommandBuffer,
    image: c.VkImage,
    old_image_layout: c.VkImageLayout,
    new_image_layout: c.VkImageLayout,
    subresource_range: c.VkImageSubresourceRange,
) !void {
    var barrier = std.mem.zeroInit(c.VkImageMemoryBarrier, .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old_image_layout,
        .newLayout = new_image_layout,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = image,
        .subresourceRange = subresource_range,
    });

    // Source layouts (old)
    // The source access mask controls actions to be finished on the old
    // layout before it will be transitioned to the new layout.
    switch (old_image_layout) {
        c.VK_IMAGE_LAYOUT_UNDEFINED => {
            // Image layout is undefined (or does not matter).
            // Only valid as initial layout. No flags required.
            barrier.srcAccessMask = 0;
        },
        c.VK_IMAGE_LAYOUT_PREINITIALIZED => {
            // Image is preinitialized.
            // Only valid as initial layout for linear images; preserves memory
            // contents. Make sure host writes have finished.
            barrier.srcAccessMask = c.VK_ACCESS_HOST_WRITE_BIT;
        },
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL => {
            // Image is a color attachment.
            // Make sure any writes to the color buffer have been finished.
            barrier.srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        },
        c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL => {
            // Image is a depth/stencil attachment.
            // Make sure any writes to the depth/stencil buffer have been finished.
            barrier.srcAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        },
        c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL => {
            // Image is a transfer source.
            // Make sure any reads from the image have been finished.
            barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_READ_BIT;
        },
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL => {
            // Image is a transfer destination.
            // Make sure any writes to the image have been finished.
            barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        },
        else => {
            vk.log.err("Unsupported old image layout: {s}", .{c.string_VkImageLayout(old_image_layout)});
            return error.UnsupportedImageLayout;
        },
    }

    // Target layouts (new)
    // The destination access mask controls the dependency for the new image
    // layout.
    switch (new_image_layout) {
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL => {
            // Image will be used as a transfer destination.
            // Make sure any writes to the image have finished.
            barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        },
        c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL => {
            // Image will be used as a transfer source.
            // Make sure any reads from and writes to the image have finished.
            barrier.srcAccessMask |= c.VK_ACCESS_TRANSFER_READ_BIT;
            barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_READ_BIT;
        },
        c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL => {
            // Image will be used as a color attachment.
            // Make sure any writes to the color buffer have finished.
            barrier.srcAccessMask |= c.VK_ACCESS_TRANSFER_READ_BIT;
            barrier.dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        },
        c.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL => {
            // Image layout will be used as a depth/stencil attachment.
            // Make sure any writes to depth/stencil buffer have finished.
            barrier.dstAccessMask = c.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
        },
        c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL => {
            // Image will be read in a shader (sampler, input attachment).
            // Make sure any writes to the image have finished.
            if (barrier.srcAccessMask == 0) {
                barrier.srcAccessMask = c.VK_ACCESS_HOST_WRITE_BIT | c.VK_ACCESS_TRANSFER_WRITE_BIT;
            }
            barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        },
        else => {
            vk.log.err("Unsupported new image layout: {s}", .{c.string_VkImageLayout(new_image_layout)});
            return error.UnsupportedImageLayout;
        },
    }

    const src_stage_flags = c.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
    const dest_stage_flags = c.VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;

    vk.device.cmdPipelineBarrier(
        command_buffer,
        src_stage_flags,
        dest_stage_flags,
        0,
        0,
        null,
        0,
        null,
        1,
        &barrier,
    );
}
