const std = @import("std");

const platform = @import("../../platform/platform.zig");
const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// SwapChainSupportDetails
// *********************************************************************************************

pub const SwapChainSupportDetails = struct {
    allocator: std.mem.Allocator,
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    pub fn init(
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) !SwapChainSupportDetails {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        try vk.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            physical_device,
            surface,
            &capabilities,
        );

        const formats = try vk.instance.getPhysicalDeviceSurfaceFormatsKHRAlloc(
            allocator,
            physical_device,
            surface,
        );
        errdefer allocator.free(formats);

        const present_modes = try vk.instance.getPhysicalDeviceSurfacePresentModesKHRAlloc(
            allocator,
            physical_device,
            surface,
        );
        errdefer allocator.free(present_modes);

        return .{
            .allocator = allocator,
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }

    pub fn deinit(self: *const SwapChainSupportDetails) void {
        self.allocator.free(self.formats);
        self.allocator.free(self.present_modes);
    }
};

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const SwapChain = struct {
    allocator: std.mem.Allocator,
    handle: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,
    extent: c.VkExtent2D,
    format: c.VkFormat,
    frame_buffers: ?[]c.VkFramebuffer,
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn chooseSwapSurfaceFormat(formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }
    return formats[0];
}

fn chooseSwapPresentMode(present_modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (present_modes) |present_mode| {
        if (present_mode == c.VK_PRESENT_MODE_MAILBOX_KHR) {
            return present_mode;
        }
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(
    capabilities: *c.VkSurfaceCapabilitiesKHR,
    window_width: u32,
    window_height: u32,
) c.VkExtent2D {
    if (capabilities.currentExtent.width != c.UINT32_MAX) {
        return capabilities.currentExtent;
    }

    var actual_extent = c.VkExtent2D{
        .width = window_width,
        .height = window_height,
    };

    actual_extent.width = std.math.clamp(
        actual_extent.width,
        capabilities.minImageExtent.width,
        capabilities.maxImageExtent.width,
    );
    actual_extent.height = std.math.clamp(
        actual_extent.height,
        capabilities.minImageExtent.height,
        capabilities.maxImageExtent.height,
    );

    return actual_extent;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn create(
    surface: c.VkSurfaceKHR,
    width: u32,
    height: u32,
) !SwapChain {
    var swap_chain_support = try SwapChainSupportDetails.init(
        vk.arena,
        vk.device.physical_device,
        surface,
    );
    defer swap_chain_support.deinit();

    const surface_format = chooseSwapSurfaceFormat(swap_chain_support.formats);
    const present_mode = chooseSwapPresentMode(swap_chain_support.present_modes);

    const extent = chooseSwapExtent(
        &swap_chain_support.capabilities,
        width,
        height,
    );

    var image_count = swap_chain_support.capabilities.minImageCount + 1;
    if (swap_chain_support.capabilities.maxImageCount > 0 and
        image_count > swap_chain_support.capabilities.maxImageCount)
    {
        image_count = swap_chain_support.capabilities.maxImageCount;
    }

    var create_info = std.mem.zeroInit(
        c.VkSwapchainCreateInfoKHR,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface,
            .minImageCount = image_count,
            .imageFormat = surface_format.format,
            .imageColorSpace = surface_format.colorSpace,
            .imageExtent = extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .preTransform = swap_chain_support.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = c.VK_TRUE,
            //.oldSwapchain = c.VK_NULL_HANDLE,
        },
    );

    const queue_family_indices = vk.device.queue_family_indices;
    const queue_family_indices_array = [_]u32{
        queue_family_indices.graphics_family.?,
        queue_family_indices.present_family.?,
    };

    if (queue_family_indices.graphics_family != queue_family_indices.present_family) {
        create_info.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        create_info.queueFamilyIndexCount = 2;
        create_info.pQueueFamilyIndices = &queue_family_indices_array;
    } else {
        create_info.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    }

    var swap_chain: c.VkSwapchainKHR = undefined;
    try vk.device.createSwapchainKHR(
        &create_info,
        &swap_chain,
    );
    errdefer vk.device.destroySwapchainKHR(swap_chain);

    vk.log.debug("Swap chain created:", .{});
    vk.log.debug("  - Image count: {d}", .{image_count});
    vk.log.debug("  - Image format: {s}", .{c.string_VkFormat(surface_format.format)});
    vk.log.debug("  - Image color space: {s}", .{c.string_VkColorSpaceKHR(surface_format.colorSpace)});
    vk.log.debug("  - Image extent: {d}x{d}", .{ extent.width, extent.height });
    vk.log.debug("  - Present mode: {s}", .{c.string_VkPresentModeKHR(present_mode)});

    const swap_chain_images = try vk.device.getSwapchainImagesKHRAlloc(
        vk.gpa,
        swap_chain,
    );
    errdefer vk.gpa.free(swap_chain_images);

    var swap_chain_image_views = try vk.gpa.alloc(
        c.VkImageView,
        swap_chain_images.len,
    );
    errdefer vk.gpa.free(swap_chain_image_views);

    @memset(swap_chain_image_views, null);
    errdefer {
        for (swap_chain_image_views) |image_view| {
            if (image_view != null) {
                vk.device.destroyImageView(image_view);
            }
        }
    }

    for (swap_chain_images, 0..) |swap_chain_image, index| {
        const image_view_create_info = std.mem.zeroInit(
            c.VkImageViewCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = swap_chain_image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = surface_format.format,
                .components = c.VkComponentMapping{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            },
        );

        try vk.device.createImageView(
            &image_view_create_info,
            &swap_chain_image_views[index],
        );
    }

    return SwapChain{
        .allocator = vk.gpa,
        .handle = swap_chain,
        .images = swap_chain_images,
        .image_views = swap_chain_image_views,
        .extent = extent,
        .format = surface_format.format,
        .frame_buffers = null,
    };
}

pub fn destroy(swapchain: *SwapChain) void {
    if (swapchain.frame_buffers) |frame_buffers| {
        for (frame_buffers) |frame_buffer| {
            vk.device.destroyFrameBuffer(frame_buffer);
        }
        swapchain.allocator.free(frame_buffers);
    }

    for (swapchain.image_views) |image_view| {
        vk.device.destroyImageView(image_view);
    }
    swapchain.allocator.free(swapchain.image_views);
    swapchain.allocator.free(swapchain.images);
    vk.device.destroySwapchainKHR(swapchain.handle);
}

pub fn createFrameBuffers(
    swapchain: *SwapChain,
    render_pass: c.VkRenderPass,
    depth_image_view: c.VkImageView,
) !void {
    swapchain.frame_buffers = try swapchain.allocator.alloc(
        c.VkFramebuffer,
        swapchain.image_views.len,
    );

    for (swapchain.image_views, 0..) |image_view, index| {
        const attachments = [2]c.VkImageView{ image_view, depth_image_view };

        const frame_buffer_create_info = std.mem.zeroInit(
            c.VkFramebufferCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = render_pass,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments,
                .width = swapchain.extent.width,
                .height = swapchain.extent.height,
                .layers = 1,
            },
        );

        try vk.device.createFrameBuffer(
            &frame_buffer_create_info,
            &swapchain.frame_buffers.?[index],
        );
    }
}
