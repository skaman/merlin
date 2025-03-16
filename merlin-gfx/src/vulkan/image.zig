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
};

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn create(
    width: u32,
    height: u32,
    format: c.VkFormat,
    tiling: c.VkImageTiling,
    usage: c.VkImageUsageFlags,
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
                .depth = 1,
            },
            .mipLevels = 1,
            .arrayLayers = 1,
            .format = format,
            .tiling = tiling,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
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

    return .{ .image = image, .memory = memory };
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

//pub fn transitionLayout(
//    command_pool: c.VkCommandPool,
//    image: c.VkImage,
//    //format: c.VkFormat,
//    old_layout: c.VkImageLayout,
//    new_layout: c.VkImageLayout,
//) !void {
//    std.debug.assert(image != null);
//    std.debug.assert(old_layout != new_layout);
//
//    var command_buffer = try vk.command_buffers.create(
//        command_pool,
//        1,
//    );
//    defer vk.command_buffers.destroy(&command_buffer);
//
//    try command_buffer.begin(0, true);
//
//    const barrier = std.mem.zeroInit(
//        c.VkImageMemoryBarrier,
//        .{
//            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
//            .oldLayout = old_layout,
//            .newLayout = new_layout,
//            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
//            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
//            .image = image,
//            .subresourceRange = .{
//                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
//                .baseMipLevel = 0,
//                .levelCount = 1,
//                .baseArrayLayer = 0,
//                .layerCount = 1,
//            },
//        },
//    );
//
//    var source_stage: c.VkPipelineStageFlags = 0;
//    var destination_stage: c.VkPipelineStageFlags = 0;
//
//    if (old_layout == c.VK_IMAGE_LAYOUT_UNDEFINED and
//        new_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
//    {
//        barrier.srcAccessMask = 0;
//        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
//
//        source_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
//        destination_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
//    } else if (old_layout == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and
//        new_layout == c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
//    {
//        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
//        barrier.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
//
//        source_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
//        destination_stage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
//    } else {
//        vk.log.err("Unsupported layout transition");
//        return error.UnsupportedTransition;
//    }
//
//    command_buffer.pipelineBarrier(
//        0,
//        source_stage,
//        destination_stage,
//        0,
//        0,
//        null,
//        0,
//        null,
//        1,
//        &barrier,
//    );
//}
