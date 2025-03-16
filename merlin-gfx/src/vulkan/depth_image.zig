const std = @import("std");

const platform = @import("../../platform/platform.zig");
const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const DepthImage = struct {
    image: vk.image.Image,
    view: c.VkImageView,
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn findSupportedFormat(
    candidates: []const c.VkFormat,
    tiling: c.VkImageTiling,
    features: c.VkFormatFeatureFlags,
) !c.VkFormat {
    for (candidates) |format| {
        var properties: c.VkFormatProperties = undefined;
        vk.instance.getPhysicalDeviceFormatProperties(
            vk.device.physical_device,
            format,
            &properties,
        );

        if (tiling == c.VK_IMAGE_TILING_LINEAR and
            (properties.linearTilingFeatures & features) == features)
        {
            return format;
        }

        if (tiling == c.VK_IMAGE_TILING_OPTIMAL and
            (properties.optimalTilingFeatures & features) == features)
        {
            return format;
        }
    }

    vk.log.err("Failed to find supported format", .{});
    return error.UnsupportedFormat;
}

fn hasStencilComponent(format: c.VkFormat) bool {
    return format == c.VK_FORMAT_D32_SFLOAT_S8_UINT or
        format == c.VK_FORMAT_D24_UNORM_S8_UINT;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn findDepthFormat() !c.VkFormat {
    return findSupportedFormat(
        &[_]c.VkFormat{
            c.VK_FORMAT_D32_SFLOAT,
            c.VK_FORMAT_D32_SFLOAT_S8_UINT,
            c.VK_FORMAT_D24_UNORM_S8_UINT,
        },
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
    );
}

pub fn create(
    //surface: c.VkSurfaceKHR,
    width: u32,
    height: u32,
) !DepthImage {
    const depth_format = try findDepthFormat();

    const image = try vk.image.create(
        width,
        height,
        depth_format,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    const image_view = try vk.image.createView(
        image.image,
        depth_format,
        c.VK_IMAGE_VIEW_TYPE_2D,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        1,
        1,
    );

    return .{
        .image = image,
        .view = image_view,
    };
}

pub fn destroy(depth_image: DepthImage) void {
    vk.image.destroyView(depth_image.view);
    vk.image.destroy(depth_image.image);
}
