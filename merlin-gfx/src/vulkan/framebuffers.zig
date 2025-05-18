const std = @import("std");
const builtin = @import("builtin");

const platform = @import("merlin_platform");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Dispatch = struct {
    DestroySurfaceKHR: std.meta.Child(c.PFN_vkDestroySurfaceKHR) = undefined,
};

pub const Framebuffer = struct {
    window_handle: platform.WindowHandle,
    surface: c.VkSurfaceKHR,
    swap_chain: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,
    extent: c.VkExtent2D,
    format: c.VkFormat,
    framebuffers: []c.VkFramebuffer,
    depth_image: ?vk.image.Image,
    depth_image_view: c.VkImageView,
    framebuffer_invalidated: bool,
    render_pass: c.VkRenderPass,

    command_buffer_handles: [vk.MaxFramesInFlight]gfx.CommandBufferHandle,

    image_available_semaphores: [vk.MaxFramesInFlight]c.VkSemaphore,
    render_finished_semaphores: []c.VkSemaphore,
    in_flight_fences: [vk.MaxFramesInFlight]c.VkFence,

    current_image_index: u32,

    is_image_acquired: bool,
    is_buffer_recording: bool,
    is_destroying: bool,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _dispatch: ?Dispatch = null;
var _framebuffers: std.ArrayList(*Framebuffer) = undefined;
var _framebuffers_to_destroy: std.ArrayList(*Framebuffer) = undefined;

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

fn createWaylandSurface(window_handle: platform.WindowHandle) !c.VkSurfaceKHR {
    const createWaylandSurfaceKHR = try vk.library.get_proc(
        c.PFN_vkCreateWaylandSurfaceKHR,
        vk.instance.handle,
        "vkCreateWaylandSurfaceKHR",
    );

    vk.log.debug("Creating Wayland surface", .{});

    const create_info =
        std.mem.zeroInit(c.VkWaylandSurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
            .surface = @as(?*c.struct_wl_surface, @ptrCast(
                platform.nativeWindowHandle(window_handle),
            )),
            .display = @as(?*c.struct_wl_display, @ptrCast(
                platform.nativeDisplayHandle(),
            )),
        });
    var surface: c.VkSurfaceKHR = undefined;
    try vk.checkVulkanError(
        "Failed to create Vulkan surface",
        createWaylandSurfaceKHR(
            vk.instance.handle,
            &create_info,
            vk.instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createXlibSurface(window_handle: platform.WindowHandle) !c.VkSurfaceKHR {
    const createXlibSurfaceKHR = try vk.library.get_proc(
        c.PFN_vkCreateXlibSurfaceKHR,
        vk.instance.handle,
        "vkCreateXlibSurfaceKHR",
    );

    vk.log.debug("Creating Xlib surface", .{});

    const create_info =
        std.mem.zeroInit(c.VkXlibSurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
            .window = @as(
                c.Window,
                @intCast(@intFromPtr(platform.nativeWindowHandle(window_handle))),
            ),
            .dpy = @as(?*c.Display, @ptrCast(platform.nativeDisplayHandle())),
        });
    var surface: c.VkSurfaceKHR = undefined;
    try vk.checkVulkanError(
        "Failed to create Vulkan surface",
        createXlibSurfaceKHR(
            vk.instance.handle,
            &create_info,
            vk.instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createXcbSurface(window_handle: platform.WindowHandle) !c.VkSurfaceKHR {
    const createXcbSurfaceKHR = try vk.library.get_proc(
        c.PFN_vkCreateXcbSurfaceKHR,
        vk.instance.handle,
        "vkCreateXcbSurfaceKHR",
    );

    vk.log.debug("Creating Xcb surface", .{});

    var xcblib = try std.DynLib.open("libX11-xcb.so.1");
    defer xcblib.close();

    const XGetXCBConnection = *const fn (?*c.Display) callconv(.c) ?*c.xcb_connection_t;
    const get_xcb_connection = xcblib.lookup(
        XGetXCBConnection,
        "XGetXCBConnection",
    ) orelse {
        vk.log.err("Failed to load XGetXCBConnection", .{});
        return error.LoadLibraryFailed;
    };

    const connection =
        get_xcb_connection(@ptrCast(platform.nativeDisplayHandle()));
    if (connection == null) {
        vk.log.err("Failed to get XCB connection", .{});
        return error.GetProcAddressFailed;
    }

    const create_info =
        std.mem.zeroInit(c.VkXcbSurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
            .connection = connection,
            .window = @as(
                c.xcb_window_t,
                @intCast(@intFromPtr(platform.nativeWindowHandle(window_handle))),
            ),
        });
    var surface: c.VkSurfaceKHR = undefined;
    try vk.checkVulkanError(
        "Failed to create Vulkan surface",
        createXcbSurfaceKHR(
            vk.instance.handle,
            &create_info,
            vk.instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

// Something is wrong with HWND alignment, so we need to use a opaque pointer and bypass
// the c includes
pub const struct_VkWin32SurfaceCreateInfoKHR = extern struct {
    sType: c.VkStructureType = std.mem.zeroes(c.VkStructureType),
    pNext: ?*const anyopaque = std.mem.zeroes(?*const anyopaque),
    flags: c.VkWin32SurfaceCreateFlagsKHR = std.mem.zeroes(c.VkWin32SurfaceCreateFlagsKHR),
    hinstance: ?*anyopaque,
    hwnd: ?*anyopaque,
};

pub const PFN_vkCreateWin32SurfaceKHR = ?*const fn (
    c.VkInstance,
    [*c]const struct_VkWin32SurfaceCreateInfoKHR,
    [*c]const c.VkAllocationCallbacks,
    [*c]c.VkSurfaceKHR,
) callconv(.c) c.VkResult;

fn createWin32Surface(window_handle: platform.WindowHandle) !c.VkSurfaceKHR {
    const createWin32SurfaceKHR = try vk.library.get_proc(
        PFN_vkCreateWin32SurfaceKHR,
        vk.instance.handle,
        "vkCreateWin32SurfaceKHR",
    );

    vk.log.debug("Creating Win32 surface", .{});

    const create_info = std.mem.zeroInit(
        struct_VkWin32SurfaceCreateInfoKHR,
        .{
            .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
            .hwnd = platform.nativeWindowHandle(window_handle),
        },
    );
    var surface: c.VkSurfaceKHR = undefined;
    try vk.checkVulkanError(
        "Failed to create Vulkan surface",
        createWin32SurfaceKHR(
            vk.instance.handle,
            &create_info,
            vk.instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createCocoaSurface(window_handle: platform.WindowHandle) !c.VkSurfaceKHR {
    const createMacOSSurfaceMVK = try vk.library.get_proc(
        c.PFN_vkCreateMacOSSurfaceMVK,
        vk.instance.handle,
        "vkCreateMacOSSurfaceMVK",
    );

    vk.log.debug("Creating Cocoa surface", .{});

    const create_info = std.mem.zeroInit(
        c.VkMacOSSurfaceCreateInfoMVK,
        .{
            .sType = c.VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK,
            .pView = @as(?*c.id, @ptrCast(platform.nativeWindowHandle(window_handle))),
        },
    );
    var surface: c.VkSurfaceKHR = undefined;
    try vk.checkVulkanError(
        "Failed to create Vulkan surface",
        createMacOSSurfaceMVK(
            vk.instance.handle,
            &create_info,
            vk.instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createSwapchain(
    surface: c.VkSurfaceKHR,
    extent: c.VkExtent2D,
    swpachain_support: vk.device.SwapChainSupportDetails,
    surface_format: c.VkSurfaceFormatKHR,
    present_mode: c.VkPresentModeKHR,
) !c.VkSwapchainKHR {
    std.debug.assert(surface != null);
    std.debug.assert(extent.height > 0 and extent.width > 0);
    std.debug.assert(surface_format.format != c.VK_FORMAT_UNDEFINED);

    var image_count = swpachain_support.capabilities.minImageCount + 1;
    if (swpachain_support.capabilities.maxImageCount > 0 and
        image_count > swpachain_support.capabilities.maxImageCount)
    {
        image_count = swpachain_support.capabilities.maxImageCount;
    }
    std.debug.assert(image_count > 0);

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
            .preTransform = swpachain_support.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = c.VK_TRUE,
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

    var swapchain: c.VkSwapchainKHR = null;
    try vk.device.createSwapchainKHR(
        &create_info,
        &swapchain,
    );
    errdefer vk.device.destroySwapchainKHR(swapchain);
    std.debug.assert(swapchain != null);

    vk.log.debug("Swapchain created:", .{});
    vk.log.debug("  - Image count: {d}", .{image_count});
    vk.log.debug("  - Image format: {s}", .{
        c.string_VkFormat(surface_format.format),
    });
    vk.log.debug("  - Image color space: {s}", .{
        c.string_VkColorSpaceKHR(surface_format.colorSpace),
    });
    vk.log.debug("  - Image extent: {d}x{d}", .{ extent.width, extent.height });
    vk.log.debug("  - Present mode: {s}", .{
        c.string_VkPresentModeKHR(present_mode),
    });

    return swapchain;
}

fn destroySwapchain(swapchain: c.VkSwapchainKHR) void {
    std.debug.assert(swapchain != null);

    vk.device.destroySwapchainKHR(swapchain);
    vk.log.debug("Swapchain destroyed", .{});
}

fn createSwapchainImages(swapchain: c.VkSwapchainKHR) ![]c.VkImage {
    std.debug.assert(swapchain != null);

    const images = try vk.device.getSwapchainImagesKHRAlloc(
        vk.gpa,
        swapchain,
    );
    std.debug.assert(images.len > 0);

    vk.log.debug("Swapchain images ({d}) created", .{images.len});

    return images;
}

fn destroySwapchainImages(images: []c.VkImage) void {
    vk.gpa.free(images);

    vk.log.debug("Swapchain images destroyed", .{});
}

fn createImageViews(images: []c.VkImage, format: c.VkFormat) ![]c.VkImageView {
    std.debug.assert(images.len > 0);
    std.debug.assert(std.mem.indexOf(
        c.VkImage,
        images,
        &[_]c.VkImage{null},
    ) == null);
    std.debug.assert(format != c.VK_FORMAT_UNDEFINED);

    var image_views = try vk.gpa.alloc(
        c.VkImageView,
        images.len,
    );
    errdefer vk.gpa.free(image_views);

    @memset(image_views, null);
    errdefer {
        for (image_views) |image_view| {
            if (image_view != null) {
                vk.device.destroyImageView(image_view);
            }
        }
    }

    for (images, 0..) |image, index| {
        const image_view_create_info = std.mem.zeroInit(
            c.VkImageViewCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = format,
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
            &image_views[index],
        );

        std.debug.assert(image_views[index] != null);
    }

    vk.log.debug("Image views ({d}) created", .{image_views.len});

    return image_views;
}

fn destroyImageViews(image_views: []c.VkImageView) void {
    std.debug.assert(std.mem.indexOf(
        c.VkImageView,
        image_views,
        &[_]c.VkImageView{null},
    ) == null);

    for (image_views) |image_view| {
        vk.device.destroyImageView(image_view);
    }
    vk.gpa.free(image_views);

    vk.log.debug("Image views destroyed", .{});
}

fn createDepthImage(extent: c.VkExtent2D, format: c.VkFormat) !vk.image.Image {
    std.debug.assert(extent.width > 0 and extent.height > 0);

    const depth_image = try vk.image.create(
        extent.width,
        extent.height,
        1,
        format,
        1,
        1,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    vk.log.debug("Depth image created", .{});

    return depth_image;
}

fn destroyDepthImage(depth_image: vk.image.Image) void {
    vk.image.destroy(depth_image);

    vk.log.debug("Depth image destroyed", .{});
}

fn createDepthImageView(image: vk.image.Image) !c.VkImageView {
    const image_view = try vk.image.createView(
        image.image,
        image.format,
        c.VK_IMAGE_VIEW_TYPE_2D,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        1,
        1,
    );
    std.debug.assert(image_view != null);

    vk.log.debug("Depth image view created", .{});

    return image_view;
}

fn destroyDepthImageView(image_view: c.VkImageView) void {
    std.debug.assert(image_view != null);

    vk.device.destroyImageView(image_view);
    vk.log.debug("Depth image view destroyed", .{});
}

fn createFrameBuffers(
    image_views: []c.VkImageView,
    depth_image_view: c.VkImageView,
    extent: c.VkExtent2D,
    render_pass: c.VkRenderPass,
) ![]c.VkFramebuffer {
    std.debug.assert(image_views.len > 0);
    std.debug.assert(std.mem.indexOf(
        c.VkImageView,
        image_views,
        &[_]c.VkImageView{null},
    ) == null);
    std.debug.assert(extent.width > 0 and extent.height > 0);
    std.debug.assert(render_pass != null);

    const framebuffers = try vk.gpa.alloc(
        c.VkFramebuffer,
        image_views.len,
    );
    errdefer vk.gpa.free(framebuffers);

    @memset(framebuffers, null);
    errdefer {
        for (framebuffers) |framebuffer| {
            if (framebuffer != null) {
                vk.device.destroyFrameBuffer(framebuffer);
            }
        }
    }

    for (image_views, 0..) |image_view, index| {
        const attachments_count: usize = if (depth_image_view != null) 2 else 1;
        const attachments = try vk.arena.alloc(c.VkImageView, attachments_count);
        attachments[0] = image_view;
        if (depth_image_view != null) {
            attachments[1] = depth_image_view;
        }

        const frame_buffer_create_info = std.mem.zeroInit(
            c.VkFramebufferCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = render_pass,
                .attachmentCount = @as(u32, @intCast(attachments.len)),
                .pAttachments = attachments.ptr,
                .width = extent.width,
                .height = extent.height,
                .layers = 1,
            },
        );

        try vk.device.createFrameBuffer(
            &frame_buffer_create_info,
            &framebuffers[index],
        );

        std.debug.assert(framebuffers[index] != null);
    }

    vk.log.debug("Framebuffers ({d}) created", .{framebuffers.len});

    return framebuffers;
}

fn destroyFrameBuffers(framebuffers: []c.VkFramebuffer) void {
    std.debug.assert(std.mem.indexOf(
        c.VkFramebuffer,
        framebuffers,
        &[_]c.VkFramebuffer{null},
    ) == null);

    for (framebuffers) |framebuffer| {
        vk.device.destroyFrameBuffer(framebuffer);
    }
    vk.gpa.free(framebuffers);

    vk.log.debug("Framebuffers destroyed", .{});
}

fn createSemaphores(semaphores: []c.VkSemaphore) !void {
    std.debug.assert(semaphores.len > 0);

    @memset(semaphores, null);
    errdefer {
        for (semaphores) |semaphore| {
            if (semaphore != null) {
                vk.device.destroySemaphore(semaphore);
            }
        }
    }

    const semaphore_create_info = std.mem.zeroInit(
        c.VkSemaphoreCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        },
    );

    for (0..semaphores.len) |i| {
        try vk.device.createSemaphore(
            &semaphore_create_info,
            &semaphores[i],
        );

        std.debug.assert(semaphores[i] != null);
    }

    vk.log.debug("Semaphores ({d}) created", .{semaphores.len});
}

fn destroySemaphores(semaphores: []c.VkSemaphore) void {
    std.debug.assert(std.mem.indexOf(
        c.VkSemaphore,
        semaphores,
        &[_]c.VkSemaphore{null},
    ) == null);

    for (semaphores) |semaphore| {
        vk.device.destroySemaphore(semaphore);
    }

    vk.log.debug("Semaphores destroyed", .{});
}

fn createFences(fences: []c.VkFence) !void {
    std.debug.assert(fences.len > 0);

    @memset(fences, null);
    errdefer {
        for (fences) |fence| {
            if (fence != null) {
                vk.device.destroyFence(fence);
            }
        }
    }

    const fence_create_info = std.mem.zeroInit(
        c.VkFenceCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        },
    );
    for (0..fences.len) |i| {
        try vk.device.createFence(
            &fence_create_info,
            &fences[i],
        );

        std.debug.assert(fences[i] != null);
    }

    vk.log.debug("Fences ({d}) created", .{fences.len});
}

fn destroyFences(fences: []c.VkFence) void {
    std.debug.assert(std.mem.indexOf(
        c.VkFence,
        fences,
        &[_]c.VkFence{null},
    ) == null);

    for (fences) |fence| {
        vk.device.destroyFence(fence);
    }

    vk.log.debug("Fences destroyed", .{});
}

fn createCommandBuffers(
    command_pool: c.VkCommandPool,
    command_buffers: []gfx.CommandBufferHandle,
) !void {
    std.debug.assert(command_pool != null);
    std.debug.assert(command_buffers.len > 0);

    var created_command_buffers: u32 = 0;
    errdefer {
        for (0..created_command_buffers) |i| {
            vk.command_buffers.destroy(command_buffers[i]);
        }
    }
    for (command_buffers) |*command_buffer| {
        command_buffer.* = try vk.command_buffers.create(command_pool);
        created_command_buffers += 1;
    }

    vk.log.debug("Command buffers ({d}) created", .{created_command_buffers});
}

fn destroyCommandBuffers(command_buffers: []gfx.CommandBufferHandle) void {
    std.debug.assert(command_buffers.len > 0);
    for (command_buffers) |command_buffer| {
        vk.command_buffers.destroy(command_buffer);
    }

    vk.log.debug("Command buffers destroyed", .{});
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _framebuffers = .init(vk.gpa);
    errdefer _framebuffers.deinit();

    _framebuffers_to_destroy = .init(vk.gpa);
    errdefer _framebuffers_to_destroy.deinit();
}

pub fn deinit() void {
    _framebuffers_to_destroy.deinit();
    _framebuffers.deinit();
}

pub fn create(
    window_handle: platform.WindowHandle,
    command_pool: c.VkCommandPool,
    render_pass_handle: gfx.RenderPassHandle,
) !gfx.FramebufferHandle {
    std.debug.assert(command_pool != null);

    const framebuffer_size = platform.windowFramebufferSize(window_handle);
    std.debug.assert(framebuffer_size[0] > 0 and framebuffer_size[1] > 0);

    const surface = try createSurface(window_handle);
    errdefer destroySurface(surface);
    std.debug.assert(surface != null);

    var swapchain_support = try vk.device.SwapChainSupportDetails.init(
        vk.arena,
        vk.device.physical_device,
        surface,
    );
    defer swapchain_support.deinit();

    const surface_format = chooseSwapSurfaceFormat(swapchain_support.formats);
    const present_mode = chooseSwapPresentMode(swapchain_support.present_modes);

    const extent = chooseSwapExtent(
        &swapchain_support.capabilities,
        framebuffer_size[0],
        framebuffer_size[1],
    );
    std.debug.assert(extent.width > 0 and extent.height > 0);

    const swapchain = try createSwapchain(
        surface,
        extent,
        swapchain_support,
        surface_format,
        present_mode,
    );
    errdefer destroySwapchain(swapchain);
    std.debug.assert(swapchain != null);

    const images = try createSwapchainImages(swapchain);
    errdefer destroySwapchainImages(images);
    std.debug.assert(images.len > 0);
    std.debug.assert(std.mem.indexOf(
        c.VkImage,
        images,
        &[_]c.VkImage{null},
    ) == null);

    const image_views = try createImageViews(
        images,
        surface_format.format,
    );
    errdefer destroyImageViews(image_views);
    std.debug.assert(image_views.len == images.len);
    std.debug.assert(std.mem.indexOf(
        c.VkImageView,
        image_views,
        &[_]c.VkImageView{null},
    ) == null);

    var depth_image: ?vk.image.Image = null;
    errdefer if (depth_image != null) destroyDepthImage(depth_image.?);

    var depth_image_view: c.VkImageView = null;
    errdefer if (depth_image_view != null) destroyDepthImageView(depth_image_view);

    const render_pass = vk.render_pass.get(render_pass_handle);
    if (render_pass.depth_image) |depth_image_info| {
        depth_image = try createDepthImage(extent, depth_image_info.format);
        depth_image_view = try createDepthImageView(depth_image.?);
        std.debug.assert(depth_image_view != null);
    }

    const framebuffers = try createFrameBuffers(
        image_views,
        depth_image_view,
        extent,
        render_pass.handle,
    );
    errdefer destroyFrameBuffers(framebuffers);
    std.debug.assert(framebuffers.len == image_views.len);
    std.debug.assert(std.mem.indexOf(
        c.VkFramebuffer,
        framebuffers,
        &[_]c.VkFramebuffer{null},
    ) == null);

    var image_available_semaphores: [vk.MaxFramesInFlight]c.VkSemaphore = undefined;
    try createSemaphores(&image_available_semaphores);
    errdefer destroySemaphores(&image_available_semaphores);

    const render_finished_semaphores = try vk.gpa.alloc(
        c.VkSemaphore,
        images.len,
    );
    errdefer vk.gpa.free(render_finished_semaphores);
    try createSemaphores(render_finished_semaphores);
    errdefer destroySemaphores(render_finished_semaphores);

    var in_flight_fences: [vk.MaxFramesInFlight]c.VkFence = undefined;
    try createFences(&in_flight_fences);
    errdefer destroyFences(&in_flight_fences);

    var command_buffer_handles: [vk.MaxFramesInFlight]gfx.CommandBufferHandle = undefined;
    try createCommandBuffers(
        command_pool,
        &command_buffer_handles,
    );
    errdefer destroyCommandBuffers(&command_buffer_handles);

    const framebuffer = try vk.gpa.create(Framebuffer);
    errdefer vk.gpa.destroy(framebuffer);

    framebuffer.* = .{
        .window_handle = window_handle,
        .surface = surface,
        .swap_chain = swapchain,
        .images = images,
        .image_views = image_views,
        .extent = extent,
        .format = surface_format.format,
        .framebuffers = framebuffers,
        .depth_image = depth_image,
        .depth_image_view = depth_image_view,
        .framebuffer_invalidated = false,
        .render_pass = render_pass.handle,

        .command_buffer_handles = command_buffer_handles,

        .image_available_semaphores = image_available_semaphores,
        .render_finished_semaphores = render_finished_semaphores,
        .in_flight_fences = in_flight_fences,

        .current_image_index = 0,

        .is_image_acquired = false,
        .is_buffer_recording = false,
        .is_destroying = false,
    };

    try _framebuffers.append(framebuffer);

    return .{ .handle = @ptrCast(framebuffer) };
}

pub fn destroy(handle: gfx.FramebufferHandle) void {
    const framebuffer = get(handle);
    framebuffer.is_destroying = true;

    _framebuffers_to_destroy.append(framebuffer) catch |err| {
        vk.log.err("Failed to append framebuffer to destroy list: {any}", .{err});
        return;
    };
}

pub fn destroyPendingResources() !void {
    for (_framebuffers_to_destroy.items) |framebuffer| {
        const index = std.mem.indexOf(
            *Framebuffer,
            _framebuffers.items,
            &[_]*Framebuffer{framebuffer},
        );
        std.debug.assert(index != null);
        _ = _framebuffers.swapRemove(index.?);

        try vk.device.deviceWaitIdle();

        destroyCommandBuffers(&framebuffer.command_buffer_handles);
        destroyFences(&framebuffer.in_flight_fences);
        destroySemaphores(&framebuffer.image_available_semaphores);
        destroySemaphores(framebuffer.render_finished_semaphores);
        vk.gpa.free(framebuffer.render_finished_semaphores);
        destroyFrameBuffers(framebuffer.framebuffers);
        if (framebuffer.depth_image_view != null) {
            destroyDepthImageView(framebuffer.depth_image_view);
        }
        if (framebuffer.depth_image != null) {
            destroyDepthImage(framebuffer.depth_image.?);
        }
        destroyImageViews(framebuffer.image_views);
        destroySwapchainImages(framebuffer.images);
        destroySwapchain(framebuffer.swap_chain);
        destroySurface(framebuffer.surface);

        vk.gpa.destroy(framebuffer);
    }
    _framebuffers_to_destroy.clearRetainingCapacity();
}

pub inline fn get(handle: gfx.FramebufferHandle) *Framebuffer {
    return @ptrCast(@alignCast(handle.handle));
}

pub inline fn getAll() []*Framebuffer {
    return _framebuffers.items;
}

pub fn getSurfaceFormat(surface: c.VkSurfaceKHR) !c.VkSurfaceFormatKHR {
    std.debug.assert(surface != null);

    var swapchain_support = try vk.device.SwapChainSupportDetails.init(
        vk.arena,
        vk.device.physical_device,
        surface,
    );
    defer swapchain_support.deinit();

    return chooseSwapSurfaceFormat(swapchain_support.formats);
}

// TODO: if creation fails, we remain in an inconsistent state
// maybe we should create the new resources before destroying the old ones
// but i don't know it it's allowed by specification (need to check)
pub fn recreateSwapchain(framebuffer: *Framebuffer) !void {
    try vk.device.deviceWaitIdle();

    destroyFrameBuffers(framebuffer.framebuffers);

    if (framebuffer.depth_image_view != null) {
        destroyDepthImageView(framebuffer.depth_image_view);
    }

    var depth_image_format: ?c.VkFormat = null;
    if (framebuffer.depth_image != null) {
        depth_image_format = framebuffer.depth_image.?.format;
        destroyDepthImage(framebuffer.depth_image.?);
    }

    destroyImageViews(framebuffer.image_views);
    destroySwapchainImages(framebuffer.images);
    destroySwapchain(framebuffer.swap_chain);

    var swapchain_support = try vk.device.SwapChainSupportDetails.init(
        vk.arena,
        vk.device.physical_device,
        framebuffer.surface,
    );
    defer swapchain_support.deinit();

    const framebuffer_size = platform.windowFramebufferSize(framebuffer.window_handle);
    const surface_format = chooseSwapSurfaceFormat(swapchain_support.formats);
    const present_mode = chooseSwapPresentMode(swapchain_support.present_modes);

    const extent = chooseSwapExtent(
        &swapchain_support.capabilities,
        framebuffer_size[0],
        framebuffer_size[1],
    );
    std.debug.assert(extent.width > 0 and extent.height > 0);

    const swapchain = try createSwapchain(
        framebuffer.surface,
        extent,
        swapchain_support,
        surface_format,
        present_mode,
    );
    errdefer destroySwapchain(swapchain);
    std.debug.assert(swapchain != null);

    const images = try createSwapchainImages(swapchain);
    errdefer destroySwapchainImages(images);
    std.debug.assert(images.len > 0);
    std.debug.assert(std.mem.indexOf(
        c.VkImage,
        images,
        &[_]c.VkImage{null},
    ) == null);

    const image_views = try createImageViews(
        images,
        surface_format.format,
    );
    errdefer destroyImageViews(image_views);
    std.debug.assert(image_views.len == images.len);
    std.debug.assert(std.mem.indexOf(
        c.VkImageView,
        image_views,
        &[_]c.VkImageView{null},
    ) == null);

    var depth_image: ?vk.image.Image = null;
    errdefer if (depth_image != null) destroyDepthImage(depth_image.?);

    var depth_image_view: c.VkImageView = null;
    errdefer if (depth_image_view != null) destroyDepthImageView(depth_image_view);

    if (depth_image_format) |format| {
        depth_image = try createDepthImage(extent, format);
        depth_image_view = try createDepthImageView(depth_image.?);
        std.debug.assert(depth_image_view != null);
    }

    const framebuffers = try createFrameBuffers(
        image_views,
        depth_image_view,
        extent,
        framebuffer.render_pass,
    );
    errdefer destroyFrameBuffers(framebuffers);
    std.debug.assert(framebuffers.len == image_views.len);
    std.debug.assert(std.mem.indexOf(
        c.VkFramebuffer,
        framebuffers,
        &[_]c.VkFramebuffer{null},
    ) == null);

    framebuffer.format = surface_format.format;
    framebuffer.extent = extent;
    framebuffer.swap_chain = swapchain;
    framebuffer.images = images;
    framebuffer.image_views = image_views;
    framebuffer.depth_image = depth_image;
    framebuffer.depth_image_view = depth_image_view;
    framebuffer.framebuffers = framebuffers;
}

pub fn getSwapchainSize(handle: gfx.FramebufferHandle) [2]u32 {
    const framebuffer = get(handle);
    return .{
        framebuffer.extent.width,
        framebuffer.extent.height,
    };
}

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

pub fn createSurface(window_handle: platform.WindowHandle) !c.VkSurfaceKHR {
    if (_dispatch == null) {
        _dispatch = try vk.library.load(Dispatch, vk.instance.handle);
    }

    var surface: c.VkSurfaceKHR = undefined;
    switch (builtin.target.os.tag) {
        .windows => {
            surface = try createWin32Surface(window_handle);
        },
        .linux => {
            if (platform.nativeWindowHandleType() == .wayland) {
                surface = try createWaylandSurface(window_handle);
            } else {
                surface = createXcbSurface(window_handle) catch
                    try createXlibSurface(window_handle);
            }
        },
        .macos => {
            surface = try createCocoaSurface(window_handle);
        },
        else => {
            @compileError("Unsupported OS");
        },
    }
    std.debug.assert(surface != null);

    return surface;
}

pub fn destroySurface(surface: c.VkSurfaceKHR) void {
    std.debug.assert(_dispatch != null);

    _dispatch.?.DestroySurfaceKHR(
        vk.instance.handle,
        surface,
        vk.instance.allocation_callbacks,
    );
}
