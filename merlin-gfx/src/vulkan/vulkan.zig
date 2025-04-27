const std = @import("std");
const builtin = @import("builtin");

const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
pub const buffers = @import("buffers.zig");
pub const command_buffers = @import("command_buffers.zig");
pub const command_pool = @import("command_pool.zig");
pub const debug = @import("debug.zig");
pub const device = @import("device.zig");
pub const image = @import("image.zig");
pub const instance = @import("instance.zig");
pub const library = @import("library.zig");
pub const pipeline = @import("pipeline.zig");
pub const pipeline_layouts = @import("pipeline_layouts.zig");
pub const programs = @import("programs.zig");
pub const render_pass = @import("render_pass.zig");
pub const shaders = @import("shaders.zig");
pub const textures = @import("textures.zig");

pub const log = std.log.scoped(.gfx_vk);

pub const MaxFramesInFlight = 2;
pub const MaxDescriptorSets = 1024;

const Dispatch = struct {
    DestroySurfaceKHR: std.meta.Child(c.PFN_vkDestroySurfaceKHR) = undefined,
};

// *********************************************************************************************
// Structs
// *********************************************************************************************

const WindowContext = struct {
    surface: c.VkSurfaceKHR,
    swap_chain: c.VkSwapchainKHR,
    images: []c.VkImage,
    image_views: []c.VkImageView,
    extent: c.VkExtent2D,
    format: c.VkFormat,
    framebuffers: []c.VkFramebuffer,
    depth_image: image.Image,
    depth_image_view: c.VkImageView,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var gpa: std.mem.Allocator = undefined;
var _arena_impl: std.heap.ArenaAllocator = undefined;
pub var arena: std.mem.Allocator = undefined;

var _dispatch: ?Dispatch = null;

pub var main_window_handle: platform.WindowHandle = undefined;

var _graphics_queue: c.VkQueue = undefined;
var _present_queue: c.VkQueue = undefined;
var _transfer_queue: c.VkQueue = undefined;

var _main_window_context: WindowContext = undefined;
pub var main_render_pass: c.VkRenderPass = undefined; // TODO: this should not be public
var _main_command_buffers: [MaxFramesInFlight]gfx.CommandBufferHandle = undefined;
var _main_descriptor_pool: c.VkDescriptorPool = undefined;

var _graphics_command_pool: c.VkCommandPool = undefined;
var _transfer_command_pool: c.VkCommandPool = undefined;

var _image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var _render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
var _in_flight_fences: [MaxFramesInFlight]c.VkFence = undefined;

var _current_image_index: u32 = 0;
var _current_frame_in_flight: u32 = 0;

var _framebuffer_invalidated: bool = false;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn destroyPendingResources() void {
    buffers.destroyPendingResources();
    programs.destroyPendingResources();
    shaders.destroyPendingResources();
    textures.destroyPendingResources();
}

fn recreateSwapChain() !void {
    const framebuffer_size = platform.windowFramebufferSize(main_window_handle);
    const framebuffer_width = framebuffer_size[0];
    const framebuffer_height = framebuffer_size[1];

    if (framebuffer_width == 0 or framebuffer_height == 0) {
        _framebuffer_invalidated = true;
        return;
    }

    try device.deviceWaitIdle();

    destroyFrameBuffers(&_main_window_context);
    destroyDepthImage(&_main_window_context);
    destroySwapChain(&_main_window_context);

    try createSwapChain(
        &_main_window_context,
        framebuffer_width,
        framebuffer_height,
    );
    errdefer destroySwapChain(&_main_window_context);

    try createDepthImage(&_main_window_context);
    errdefer destroyDepthImage(&_main_window_context);

    try createFrameBuffers(
        &_main_window_context,
        main_render_pass,
    );
}

fn createWaylandSurface() !c.VkSurfaceKHR {
    const createWaylandSurfaceKHR = try library.get_proc(
        c.PFN_vkCreateWaylandSurfaceKHR,
        instance.handle,
        "vkCreateWaylandSurfaceKHR",
    );

    log.debug("Creating Wayland surface", .{});

    const create_info = std.mem.zeroInit(c.VkWaylandSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .surface = @as(?*c.struct_wl_surface, @ptrCast(platform.nativeWindowHandle(main_window_handle))),
        .display = @as(?*c.struct_wl_display, @ptrCast(platform.nativeDisplayHandle())),
    });
    var surface: c.VkSurfaceKHR = undefined;
    try checkVulkanError(
        "Failed to create Vulkan surface",
        createWaylandSurfaceKHR(
            instance.handle,
            &create_info,
            instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createXlibSurface() !c.VkSurfaceKHR {
    const createXlibSurfaceKHR = try library.get_proc(
        c.PFN_vkCreateXlibSurfaceKHR,
        instance.handle,
        "vkCreateXlibSurfaceKHR",
    );

    log.debug("Creating Xlib surface", .{});

    const create_info = std.mem.zeroInit(c.VkXlibSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
        .window = @as(c.Window, @intCast(@intFromPtr(platform.nativeWindowHandle(main_window_handle)))),
        .dpy = @as(?*c.Display, @ptrCast(platform.nativeDisplayHandle())),
    });
    var surface: c.VkSurfaceKHR = undefined;
    try checkVulkanError(
        "Failed to create Vulkan surface",
        createXlibSurfaceKHR(
            instance.handle,
            &create_info,
            instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createXcbSurface() !c.VkSurfaceKHR {
    const createXcbSurfaceKHR = try library.get_proc(
        c.PFN_vkCreateXcbSurfaceKHR,
        instance.handle,
        "vkCreateXcbSurfaceKHR",
    );

    log.debug("Creating Xcb surface", .{});

    var xcblib = try std.DynLib.open("libX11-xcb.so.1");
    defer xcblib.close();

    const XGetXCBConnection = *const fn (?*c.Display) callconv(.c) ?*c.xcb_connection_t;
    const get_xcb_connection = xcblib.lookup(
        XGetXCBConnection,
        "XGetXCBConnection",
    ) orelse {
        log.err("Failed to load XGetXCBConnection", .{});
        return error.LoadLibraryFailed;
    };

    const connection = get_xcb_connection(@ptrCast(platform.nativeDisplayHandle()));
    if (connection == null) {
        log.err("Failed to get XCB connection", .{});
        return error.GetProcAddressFailed;
    }

    const create_info = std.mem.zeroInit(c.VkXcbSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
        .connection = connection,
        .window = @as(c.xcb_window_t, @intCast(@intFromPtr(platform.nativeWindowHandle(main_window_handle)))),
    });
    var surface: c.VkSurfaceKHR = undefined;
    try checkVulkanError(
        "Failed to create Vulkan surface",
        createXcbSurfaceKHR(
            instance.handle,
            &create_info,
            instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

// Something is wront with HWND alignment, so we need to use a pointer and bypass the c includes
pub const struct_VkWin32SurfaceCreateInfoKHR = extern struct {
    sType: c.VkStructureType = @import("std").mem.zeroes(c.VkStructureType),
    pNext: ?*const anyopaque = @import("std").mem.zeroes(?*const anyopaque),
    flags: c.VkWin32SurfaceCreateFlagsKHR = @import("std").mem.zeroes(c.VkWin32SurfaceCreateFlagsKHR),
    hinstance: ?*anyopaque,
    hwnd: ?*anyopaque,
};

pub const PFN_vkCreateWin32SurfaceKHR = ?*const fn (
    c.VkInstance,
    [*c]const struct_VkWin32SurfaceCreateInfoKHR,
    [*c]const c.VkAllocationCallbacks,
    [*c]c.VkSurfaceKHR,
) callconv(.c) c.VkResult;

fn createWin32Surface() !c.VkSurfaceKHR {
    const createWin32SurfaceKHR = try library.get_proc(
        PFN_vkCreateWin32SurfaceKHR,
        instance.handle,
        "vkCreateWin32SurfaceKHR",
    );

    log.debug("Creating Win32 surface", .{});

    const window_handle = platform.nativeWindowHandle(main_window_handle);
    const create_info = std.mem.zeroInit(struct_VkWin32SurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .hwnd = window_handle,
    });
    var surface: c.VkSurfaceKHR = undefined;
    try checkVulkanError(
        "Failed to create Vulkan surface",
        createWin32SurfaceKHR(
            instance.handle,
            &create_info,
            instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createCocoaSurface() !c.VkSurfaceKHR {
    const createMacOSSurfaceMVK = try library.get_proc(
        c.PFN_vkCreateMacOSSurfaceMVK,
        instance.handle,
        "vkCreateMacOSSurfaceMVK",
    );

    log.debug("Creating Cocoa surface", .{});

    const create_info = std.mem.zeroInit(c.VkMacOSSurfaceCreateInfoMVK, .{
        .sType = c.VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK,
        .pView = @as(?*c.id, @ptrCast(platform.nativeDefaultWindowHandle())),
    });
    var surface: c.VkSurfaceKHR = undefined;
    try checkVulkanError(
        "Failed to create Vulkan surface",
        createMacOSSurfaceMVK(
            instance.handle,
            &create_info,
            instance.allocation_callbacks,
            &surface,
        ),
    );
    return surface;
}

fn createSurface() !c.VkSurfaceKHR {
    if (_dispatch == null) {
        _dispatch = try library.load(Dispatch, instance.handle);
    }

    var surface: c.VkSurfaceKHR = undefined;
    switch (builtin.target.os.tag) {
        .windows => {
            surface = try createWin32Surface();
        },
        .linux => {
            if (platform.nativeWindowHandleType() == .wayland) {
                surface = try createWaylandSurface();
            } else {
                surface = createXcbSurface() catch
                    try createXlibSurface();
            }
        },
        .macos => {
            surface = try createCocoaSurface();
        },
        else => {
            @compileError("Unsupported OS");
        },
    }

    return surface;
}

fn destroySurface(window_context: *WindowContext) void {
    std.debug.assert(_dispatch != null);

    _dispatch.?.DestroySurfaceKHR(
        instance.handle,
        window_context.surface,
        instance.allocation_callbacks,
    );
}

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

fn createSwapChain(
    window_context: *WindowContext,
    width: u32,
    height: u32,
) !void {
    var swap_chain_support = try device.SwapChainSupportDetails.init(
        arena,
        device.physical_device,
        window_context.surface,
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
            .surface = window_context.surface,
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

    const queue_family_indices = device.queue_family_indices;
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
    try device.createSwapchainKHR(
        &create_info,
        &swap_chain,
    );
    errdefer device.destroySwapchainKHR(swap_chain);

    log.debug("Swap chain created:", .{});
    log.debug("  - Image count: {d}", .{image_count});
    log.debug("  - Image format: {s}", .{c.string_VkFormat(surface_format.format)});
    log.debug("  - Image color space: {s}", .{c.string_VkColorSpaceKHR(surface_format.colorSpace)});
    log.debug("  - Image extent: {d}x{d}", .{ extent.width, extent.height });
    log.debug("  - Present mode: {s}", .{c.string_VkPresentModeKHR(present_mode)});

    const swap_chain_images = try device.getSwapchainImagesKHRAlloc(
        gpa,
        swap_chain,
    );
    errdefer gpa.free(swap_chain_images);

    var swap_chain_image_views = try gpa.alloc(
        c.VkImageView,
        swap_chain_images.len,
    );
    errdefer gpa.free(swap_chain_image_views);

    @memset(swap_chain_image_views, null);
    errdefer {
        for (swap_chain_image_views) |image_view| {
            if (image_view != null) {
                device.destroyImageView(image_view);
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

        try device.createImageView(
            &image_view_create_info,
            &swap_chain_image_views[index],
        );
    }

    window_context.swap_chain = swap_chain;
    window_context.images = swap_chain_images;
    window_context.image_views = swap_chain_image_views;
    window_context.extent = extent;
    window_context.format = surface_format.format;
}

fn destroySwapChain(window_context: *WindowContext) void {
    for (window_context.image_views) |image_view| {
        device.destroyImageView(image_view);
    }
    gpa.free(window_context.image_views);
    gpa.free(window_context.images);
    device.destroySwapchainKHR(window_context.swap_chain);
}

fn findSupportedFormat(
    candidates: []const c.VkFormat,
    tiling: c.VkImageTiling,
    features: c.VkFormatFeatureFlags,
) !c.VkFormat {
    for (candidates) |format| {
        var properties: c.VkFormatProperties = undefined;
        instance.getPhysicalDeviceFormatProperties(
            device.physical_device,
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

    log.err("Failed to find supported format", .{});
    return error.UnsupportedFormat;
}

fn hasStencilComponent(format: c.VkFormat) bool {
    return format == c.VK_FORMAT_D32_SFLOAT_S8_UINT or
        format == c.VK_FORMAT_D24_UNORM_S8_UINT;
}

fn createDepthImage(window_context: *WindowContext) !void {
    const depth_format = try findDepthFormat();

    const depth_image = try image.create(
        window_context.extent.width,
        window_context.extent.height,
        1,
        depth_format,
        1,
        1,
        c.VK_IMAGE_TILING_OPTIMAL,
        c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        c.VK_IMAGE_LAYOUT_UNDEFINED,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
    );

    const depth_image_view = try image.createView(
        depth_image.image,
        depth_format,
        c.VK_IMAGE_VIEW_TYPE_2D,
        c.VK_IMAGE_ASPECT_DEPTH_BIT,
        1,
        1,
    );

    window_context.depth_image = depth_image;
    window_context.depth_image_view = depth_image_view;
}

fn destroyDepthImage(window_context: *WindowContext) void {
    image.destroyView(window_context.depth_image_view);
    image.destroy(window_context.depth_image);
}

fn createFrameBuffers(
    window_context: *WindowContext,
    renderpass: c.VkRenderPass,
) !void {
    window_context.framebuffers = try gpa.alloc(
        c.VkFramebuffer,
        window_context.image_views.len,
    );

    for (window_context.image_views, 0..) |image_view, index| {
        const attachments = [2]c.VkImageView{
            image_view,
            window_context.depth_image_view,
        };

        const frame_buffer_create_info = std.mem.zeroInit(
            c.VkFramebufferCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                .renderPass = renderpass,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments,
                .width = window_context.extent.width,
                .height = window_context.extent.height,
                .layers = 1,
            },
        );

        try device.createFrameBuffer(
            &frame_buffer_create_info,
            &window_context.framebuffers[index],
        );
    }
}

fn destroyFrameBuffers(window_context: *WindowContext) void {
    for (window_context.framebuffers) |framebuffer| {
        device.destroyFrameBuffer(framebuffer);
    }
    gpa.free(window_context.framebuffers);
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn debugCallback(
    message_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    p_callback_data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = p_user_data;

    const allowed_flags = c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    if (message_type & allowed_flags == 0) {
        return c.VK_FALSE;
    }

    if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        log.err("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        log.warn("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
        log.info("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) {
        log.debug("{s}", .{p_callback_data.*.pMessage});
    }

    return c.VK_FALSE;
}

pub fn prepareValidationLayers(
    allocator: std.mem.Allocator,
    options: *const gfx.Options,
) !std.ArrayList([*:0]const u8) {
    var layers = std.ArrayList([*:0]const u8).init(
        allocator,
    );
    errdefer layers.deinit();

    if (options.enable_vulkan_debug) {
        try layers.append("VK_LAYER_KHRONOS_validation");
    }

    return layers;
}

pub fn checkVulkanError(comptime message: []const u8, result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) {
        log.err("{s}: {s}", .{ message, c.string_VkResult(result) });
        return error.VulkanError;
    }
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

pub fn findMemoryTypeIndex(
    memory_type_bits: u32,
    property_flags: c.VkMemoryPropertyFlags,
) !u32 {
    var memory_properties: c.VkPhysicalDeviceMemoryProperties = undefined;
    instance.getPhysicalDeviceMemoryProperties(
        device.physical_device,
        &memory_properties,
    );

    for (0..memory_properties.memoryTypeCount) |index| {
        if (memory_type_bits & (@as(u32, 1) << @as(u5, @intCast(index))) != 0 and
            memory_properties.memoryTypes[index].propertyFlags & property_flags == property_flags)
        {
            return @intCast(index);
        }
    }

    log.err("Failed to find suitable memory type", .{});

    return error.MemoryTypeNotFound;
}

// *********************************************************************************************
// Public Renderer API
// *********************************************************************************************

pub fn init(
    allocator: std.mem.Allocator,
    options: *const gfx.Options,
) !void {
    log.debug("Initializing Vulkan renderer", .{});

    gpa = allocator;

    _arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer _arena_impl.deinit();
    arena = _arena_impl.allocator();

    main_window_handle = options.window_handle;

    try library.init();
    errdefer library.deinit();

    try instance.init(options);
    errdefer instance.deinit();

    try debug.init(options);
    errdefer debug.deinit();

    _main_window_context.surface = try createSurface();
    errdefer destroySurface(&_main_window_context);

    try device.init(options, _main_window_context.surface);
    errdefer device.deinit();

    device.getDeviceQueue(
        device.queue_family_indices.graphics_family.?,
        0,
        &_graphics_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.present_family.?,
        0,
        &_present_queue,
    );

    device.getDeviceQueue(
        device.queue_family_indices.transfer_family.?,
        0,
        &_transfer_queue,
    );

    const framebuffer_size = platform.windowFramebufferSize(main_window_handle);
    const framebuffer_width = framebuffer_size[0];
    const framebuffer_height = framebuffer_size[1];

    try createSwapChain(
        &_main_window_context,
        framebuffer_width,
        framebuffer_height,
    );
    errdefer destroySwapChain(&_main_window_context);

    main_render_pass = try render_pass.create(_main_window_context.format);
    errdefer render_pass.destroy(main_render_pass);

    try createDepthImage(&_main_window_context);
    errdefer destroyDepthImage(&_main_window_context);

    try createFrameBuffers(
        &_main_window_context,
        main_render_pass,
    );
    errdefer destroyFrameBuffers(&_main_window_context);

    _graphics_command_pool = try command_pool.create(device.queue_family_indices.graphics_family.?);
    errdefer command_pool.destroy(_graphics_command_pool);

    _transfer_command_pool = try command_pool.create(device.queue_family_indices.transfer_family.?);
    errdefer command_pool.destroy(_transfer_command_pool);

    command_buffers.init();
    errdefer command_buffers.deinit();

    var created_command_buffers: u32 = 0;
    errdefer {
        for (0..created_command_buffers) |i| {
            command_buffers.destroy(_main_command_buffers[i]);
        }
    }
    for (0..MaxFramesInFlight) |i| {
        _main_command_buffers[i] = try command_buffers.create(_graphics_command_pool);
        created_command_buffers += 1;
    }

    const semaphore_create_info = std.mem.zeroInit(
        c.VkSemaphoreCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        },
    );

    const fence_create_info = std.mem.zeroInit(
        c.VkFenceCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        },
    );

    for (0..MaxFramesInFlight) |i| {
        try device.createSemaphore(
            &semaphore_create_info,
            &_image_available_semaphores[i],
        );

        try device.createSemaphore(
            &semaphore_create_info,
            &_render_finished_semaphores[i],
        );

        try device.createFence(
            &fence_create_info,
            &_in_flight_fences[i],
        );
    }

    const pool_size = std.mem.zeroInit(
        c.VkDescriptorPoolSize,
        .{
            .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = 128, // TODO: this can be calculated in advance knowing our max resources (see bgfx as example)
        },
    );

    const pool_info = std.mem.zeroInit(
        c.VkDescriptorPoolCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .maxSets = MaxDescriptorSets * MaxFramesInFlight,
            .poolSizeCount = 1,
            .pPoolSizes = &pool_size,
            .flags = c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        },
    );

    try device.createDescriptorPool(&pool_info, &_main_descriptor_pool);
    errdefer device.destroyDescriptorPool(_main_descriptor_pool);

    pipeline_layouts.init();
    pipeline.init();
    buffers.init();
    programs.init();
    shaders.init();
    textures.init();
}

pub fn deinit() void {
    log.debug("Deinitializing Vulkan renderer", .{});

    device.deviceWaitIdle() catch {
        log.err("Failed to wait for Vulkan device to become idle", .{});
    };

    destroyPendingResources();

    textures.deinit();
    shaders.deinit();
    programs.deinit();
    buffers.deinit();
    pipeline.deinit();
    pipeline_layouts.deinit();

    device.destroyDescriptorPool(_main_descriptor_pool);

    for (0..MaxFramesInFlight) |i| {
        device.destroySemaphore(_image_available_semaphores[i]);
        device.destroySemaphore(_render_finished_semaphores[i]);
        device.destroyFence(_in_flight_fences[i]);
    }

    for (0..MaxFramesInFlight) |i| {
        command_buffers.destroy(_main_command_buffers[i]);
    }
    command_buffers.deinit();

    command_pool.destroy(_graphics_command_pool);
    command_pool.destroy(_transfer_command_pool);

    render_pass.destroy(main_render_pass);
    destroyFrameBuffers(&_main_window_context);
    destroyDepthImage(&_main_window_context);
    destroySwapChain(&_main_window_context);
    destroySurface(&_main_window_context);
    device.deinit();
    debug.deinit();
    instance.deinit();
    library.deinit();

    _arena_impl.deinit();
}

pub fn swapchainSize() [2]u32 {
    return .{
        _main_window_context.extent.width,
        _main_window_context.extent.height,
    };
}

pub fn uniformAlignment() u32 {
    return @intCast(device.properties.limits.minUniformBufferOffsetAlignment);
}

pub fn maxFramesInFlight() u32 {
    return MaxFramesInFlight;
}

pub fn currentFrameInFlight() u32 {
    return _current_frame_in_flight;
}

pub fn createShader(reader: std.io.AnyReader, options: gfx.ShaderOptions) !gfx.ShaderHandle {
    return shaders.create(reader, options);
}

pub fn destroyShader(handle: gfx.ShaderHandle) void {
    shaders.destroy(handle);
}

pub fn createPipelineLayout(
    vertex_layout: types.VertexLayout,
) !gfx.PipelineLayoutHandle {
    return pipeline_layouts.create(vertex_layout);
}

pub fn destroyPipelineLayout(handle: gfx.PipelineLayoutHandle) void {
    pipeline_layouts.destroy(handle);
}

pub fn createProgram(
    vertex_shader: gfx.ShaderHandle,
    fragment_shader: gfx.ShaderHandle,
    options: gfx.ProgramOptions,
) !gfx.ProgramHandle {
    return programs.create(
        vertex_shader,
        fragment_shader,
        _main_descriptor_pool,
        options,
    );
}

pub fn destroyProgram(handle: gfx.ProgramHandle) void {
    programs.destroy(handle);
}

pub fn createBuffer(
    size: u32,
    usage: gfx.BufferUsage,
    location: gfx.BufferLocation,
    options: gfx.BufferOptions,
) !gfx.BufferHandle {
    return buffers.create(size, usage, location, options);
}

pub fn destroyBuffer(handle: gfx.BufferHandle) void {
    buffers.destroy(handle);
}

pub fn updateBuffer(
    handle: gfx.BufferHandle,
    reader: std.io.AnyReader,
    offset: u32,
    size: u32,
) !void {
    try buffers.update(
        _transfer_command_pool,
        _transfer_queue,
        handle,
        reader,
        offset,
        size,
    );
}

pub fn createTexture(reader: std.io.AnyReader, size: u32, options: gfx.TextureOptions) !gfx.TextureHandle {
    return textures.create(
        _transfer_command_pool,
        _transfer_queue,
        reader,
        size,
        options,
    );
}

pub fn createTextureFromKTX(reader: std.io.AnyReader, size: u32, options: gfx.TextureKTXOptions) !gfx.TextureHandle {
    return textures.createFromKTX(
        _transfer_command_pool,
        _transfer_queue,
        reader,
        size,
        options,
    );
}

pub fn destroyTexture(handle: gfx.TextureHandle) void {
    return textures.destroy(handle);
}

pub fn beginFrame() !bool {
    try device.waitForFences(
        1,
        &_in_flight_fences[_current_frame_in_flight],
        c.VK_TRUE,
        c.UINT64_MAX,
    );

    if (try device.acquireNextImageKHR(
        _main_window_context.swap_chain,
        c.UINT64_MAX,
        _image_available_semaphores[_current_frame_in_flight],
        null,
        &_current_image_index,
    ) == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try recreateSwapChain();
        return false;
    }

    try device.resetFences(1, &_in_flight_fences[_current_frame_in_flight]);

    try command_buffers.reset(_main_command_buffers[_current_frame_in_flight]);
    destroyPendingResources();
    try command_buffers.begin(_main_command_buffers[_current_frame_in_flight]);

    try command_buffers.beginRenderPass(
        _main_command_buffers[_current_frame_in_flight],
        main_render_pass,
        _main_window_context.framebuffers[_current_image_index],
        _main_window_context.extent,
    );

    return true;
}

pub fn endFrame() !void {
    defer _ = _arena_impl.reset(.retain_capacity);

    command_buffers.endRenderPass(_main_command_buffers[_current_frame_in_flight]);
    try command_buffers.end(_main_command_buffers[_current_frame_in_flight]);

    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const wait_semaphores = [_]c.VkSemaphore{_image_available_semaphores[_current_frame_in_flight]};
    const signal_semaphores = [_]c.VkSemaphore{_render_finished_semaphores[_current_frame_in_flight]};
    const command_buffer = command_buffers.commandBufferFromHandle(_main_command_buffers[_current_frame_in_flight]);
    const submit_info = std.mem.zeroInit(
        c.VkSubmitInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &wait_semaphores,
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer.handle,
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &signal_semaphores,
        },
    );

    try device.queueSubmit(
        _graphics_queue,
        1,
        &submit_info,
        _in_flight_fences[_current_frame_in_flight],
    );

    const present_info = std.mem.zeroInit(
        c.VkPresentInfoKHR,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &_main_window_context.swap_chain,
            .pImageIndices = &_current_image_index,
        },
    );

    const framebuffer_size = platform.windowFramebufferSize(main_window_handle);
    if (_main_window_context.extent.width != framebuffer_size[0] or _main_window_context.extent.height != framebuffer_size[1]) {
        _framebuffer_invalidated = true;
    }

    const result = try device.queuePresentKHR(_present_queue, &present_info);
    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR or _framebuffer_invalidated) {
        _framebuffer_invalidated = false;
        try recreateSwapChain();
    }

    _current_frame_in_flight = (_current_frame_in_flight + 1) % MaxFramesInFlight;
}

pub fn setViewport(position: [2]u32, size: [2]u32) void {
    const vk_viewport = std.mem.zeroInit(
        c.VkViewport,
        .{
            .x = @as(f32, @floatFromInt(position[0])),
            .y = @as(f32, @floatFromInt(position[1])),
            .width = @as(f32, @floatFromInt(size[0])),
            .height = @as(f32, @floatFromInt(size[1])),
            .minDepth = 0,
            .maxDepth = 1,
        },
    );

    command_buffers.setViewport(
        _main_command_buffers[_current_frame_in_flight],
        &vk_viewport,
    );
}

pub fn setScissor(position: [2]u32, size: [2]u32) void {
    const vk_scissor = std.mem.zeroInit(
        c.VkRect2D,
        .{
            .offset = c.VkOffset2D{
                .x = @as(i32, @intCast(position[0])),
                .y = @as(i32, @intCast(position[1])),
            },
            .extent = c.VkExtent2D{
                .width = size[0],
                .height = size[1],
            },
        },
    );
    command_buffers.setScissor(
        _main_command_buffers[_current_frame_in_flight],
        &vk_scissor,
    );
}

pub fn setDebug(debug_options: gfx.DebugOptions) void {
    command_buffers.setDebug(
        _main_command_buffers[_current_frame_in_flight],
        debug_options,
    );
}

pub fn setRender(render_options: gfx.RenderOptions) void {
    command_buffers.setRender(
        _main_command_buffers[_current_frame_in_flight],
        render_options,
    );
}

pub fn bindPipelineLayout(pipeline_layout: gfx.PipelineLayoutHandle) void {
    command_buffers.bindPipelineLayout(
        _main_command_buffers[_current_frame_in_flight],
        pipeline_layout,
    );
}

pub fn bindProgram(program: gfx.ProgramHandle) void {
    command_buffers.bindProgram(
        _main_command_buffers[_current_frame_in_flight],
        program,
    );
}

pub fn bindVertexBuffer(buffer: gfx.BufferHandle, offset: u32) void {
    command_buffers.bindVertexBuffer(
        _main_command_buffers[_current_frame_in_flight],
        buffer,
        offset,
    );
}

pub fn bindIndexBuffer(buffer: gfx.BufferHandle, offset: u32) void {
    command_buffers.bindIndexBuffer(
        _main_command_buffers[_current_frame_in_flight],
        buffer,
        offset,
    );
}

pub fn bindUniformBuffer(name: gfx.NameHandle, buffer: gfx.BufferHandle, offset: u32) void {
    command_buffers.bindUniformBuffer(
        _main_command_buffers[_current_frame_in_flight],
        name,
        buffer,
        offset,
    );
}

pub fn bindCombinedSampler(name: gfx.NameHandle, texture: gfx.TextureHandle) void {
    command_buffers.bindCombinedSampler(
        _main_command_buffers[_current_frame_in_flight],
        name,
        texture,
    );
}

pub fn pushConstants(
    shader_stage: types.ShaderType,
    offset: u32,
    data: []const u8,
) void {
    command_buffers.pushConstants(
        _main_command_buffers[_current_frame_in_flight],
        shader_stage,
        offset,
        @intCast(data.len),
        @ptrCast(data.ptr),
    );
}

pub fn draw(
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    command_buffers.draw(
        _main_command_buffers[_current_frame_in_flight],
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
    index_type: types.IndexType,
) void {
    command_buffers.drawIndexed(
        _main_command_buffers[_current_frame_in_flight],
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
        index_type,
    );
}

pub fn beginDebugLabel(
    label_name: []const u8,
    color: [4]f32,
) void {
    command_buffers.beginDebugLabel(
        _main_command_buffers[_current_frame_in_flight],
        label_name,
        color,
    );
}

pub fn endDebugLabel() void {
    command_buffers.endDebugLabel(
        _main_command_buffers[_current_frame_in_flight],
    );
}

pub fn insertDebugLabel(
    label_name: []const u8,
    color: [4]f32,
) void {
    command_buffers.insertDebugLabel(
        _main_command_buffers[_current_frame_in_flight],
        label_name,
        color,
    );
}
