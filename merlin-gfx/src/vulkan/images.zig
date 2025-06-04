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
    format: c.VkFormat,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _images_to_destroy: std.ArrayList(*const Image) = undefined;
var _image_views_to_destroy: std.ArrayList(c.VkImageView) = undefined;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _images_to_destroy = .init(vk.gpa);
    errdefer _images_to_destroy.deinit();

    _image_views_to_destroy = .init(vk.gpa);
    errdefer _image_views_to_destroy.deinit();
}

pub fn deinit() void {
    _images_to_destroy.deinit();
    _image_views_to_destroy.deinit();
}

pub fn createInternal(
    width: u32,
    height: u32,
    depth: u32,
    format: c.VkFormat,
    create_flags: c.VkImageCreateFlags,
    mip_levels: u32,
    array_layers: u32,
    tiling: c.VkImageTiling,
    usage: c.VkImageUsageFlags,
    initial_layout: c.VkImageLayout,
    properties: c.VkMemoryPropertyFlags,
    samples: c.VkSampleCountFlagBits,
) !Image {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);
    std.debug.assert(depth > 0);
    std.debug.assert(format != c.VK_FORMAT_UNDEFINED);
    std.debug.assert(mip_levels > 0);
    std.debug.assert(array_layers > 0);

    const image_info = std.mem.zeroInit(
        c.VkImageCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .flags = create_flags,
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
            .samples = samples,
            .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        },
    );

    var image: c.VkImage = undefined;
    try vk.device.createImage(&image_info, &image);
    errdefer vk.device.destroyImage(image);
    std.debug.assert(image != null);

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
    std.debug.assert(memory != null);

    try vk.device.bindImageMemory(image, memory, 0);

    return .{
        .image = image,
        .memory = memory,
        .size = memory_requirements.size,
        .format = format,
    };
}

pub fn destroyInternal(image: Image) void {
    vk.device.destroyImage(image.image);
    vk.device.freeMemory(image.memory);
}

pub fn createViewInternal(
    image: c.VkImage,
    format: c.VkFormat,
    view_type: c.VkImageViewType,
    aspect_flags: c.VkImageAspectFlags,
    level_count: u32,
    layer_count: u32,
) !c.VkImageView {
    std.debug.assert(image != null);
    std.debug.assert(format != c.VK_FORMAT_UNDEFINED);
    std.debug.assert(level_count > 0);
    std.debug.assert(layer_count > 0);

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
    std.debug.assert(view != null);
    return view;
}

pub fn destroyViewInternal(view: c.VkImageView) void {
    std.debug.assert(view != null);
    vk.device.destroyImageView(view);
}

pub fn setImageLayout(
    command_buffer: c.VkCommandBuffer,
    image: c.VkImage,
    old_image_layout: c.VkImageLayout,
    new_image_layout: c.VkImageLayout,
    subresource_range: c.VkImageSubresourceRange,
) !void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(image != null);
    std.debug.assert(old_image_layout != new_image_layout);

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
        c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR => {
            barrier.dstAccessMask = c.VK_ACCESS_MEMORY_READ_BIT;
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

pub fn create(image_options: gfx.ImageOptions) !gfx.ImageHandle {
    var usage: c.VkImageUsageFlags = 0;
    if (image_options.usage.color_attachment)
        usage |= c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (image_options.usage.depth_stencil_attachment)
        usage |= c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;

    const properties: u32 = switch (image_options.location) {
        .host => c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
            c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        .device => c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    };

    const samples: c.VkSampleCountFlagBits =
        switch (image_options.samples) {
            .one => c.VK_SAMPLE_COUNT_1_BIT,
            .two => c.VK_SAMPLE_COUNT_2_BIT,
            .four => c.VK_SAMPLE_COUNT_4_BIT,
            .eight => c.VK_SAMPLE_COUNT_8_BIT,
            .sixteen => c.VK_SAMPLE_COUNT_16_BIT,
            .thirty_two => c.VK_SAMPLE_COUNT_32_BIT,
            .sixty_four => c.VK_SAMPLE_COUNT_64_BIT,
        };

    const img = try vk.gpa.create(Image);
    img.* = try createInternal(
        image_options.width,
        image_options.height,
        image_options.depth,
        vk.vulkanFormatFromGfxImageFormat(image_options.format),
        0,
        image_options.mip_levels,
        image_options.array_layers,
        vk.textures.tilingFromGfxTextureTiling(image_options.tiling),
        usage,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        properties,
        samples,
    );
    return gfx.ImageHandle{ .handle = @ptrCast(img) };
}

pub fn destroy(handle: gfx.ImageHandle) void {
    const image: *const Image = @ptrCast(@alignCast(handle.handle));
    _images_to_destroy.append(image) catch |err| {
        vk.log.err("Failed to append image to destroy list: {any}", .{err});
        return;
    };
}

pub fn createView(
    image_handle: gfx.ImageHandle,
    options: gfx.ImageViewOptions,
) !gfx.ImageViewHandle {
    const img: *const Image = @ptrCast(@alignCast(image_handle.handle));
    const format = vk.vulkanFormatFromGfxImageFormat(options.format);

    var view_type: c.VkImageViewType = undefined;
    if (options.is_cubemap) {
        if (options.is_array) {
            view_type = c.VK_IMAGE_VIEW_TYPE_CUBE_ARRAY;
        } else {
            view_type = c.VK_IMAGE_VIEW_TYPE_CUBE;
        }
    } else {
        if (options.is_array) {
            view_type = c.VK_IMAGE_VIEW_TYPE_2D_ARRAY;
        } else {
            view_type = c.VK_IMAGE_VIEW_TYPE_2D;
        }
    }

    var aspect: c.VkImageAspectFlags = 0;
    if (options.aspect.color) aspect |= c.VK_IMAGE_ASPECT_COLOR_BIT;
    if (options.aspect.depth) aspect |= c.VK_IMAGE_ASPECT_DEPTH_BIT;
    if (options.aspect.stencil) aspect |= c.VK_IMAGE_ASPECT_STENCIL_BIT;

    const image_view = try createViewInternal(
        img.image,
        format,
        view_type,
        aspect,
        options.level_count,
        options.layer_count,
    );

    return gfx.ImageViewHandle{ .handle = @ptrCast(image_view) };
}

pub fn destroyView(handle: gfx.ImageViewHandle) void {
    const image_view: c.VkImageView = @ptrCast(@alignCast(handle.handle));
    _image_views_to_destroy.append(image_view) catch |err| {
        vk.log.err("Failed to append image view to destroy list: {any}", .{err});
        return;
    };
}

pub fn destroyPendingResources() void {
    for (_images_to_destroy.items) |image| {
        destroyInternal(image.*);
        vk.gpa.destroy(image);
    }
    for (_image_views_to_destroy.items) |view| {
        destroyViewInternal(view);
    }
    _images_to_destroy.clearRetainingCapacity();
    _image_views_to_destroy.clearRetainingCapacity();
}
