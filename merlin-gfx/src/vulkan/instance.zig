const std = @import("std");
const builtin = @import("builtin");

const platform = @import("merlin_platform");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

const Dispatch = struct {
    CreateDevice: std.meta.Child(c.PFN_vkCreateDevice) = undefined,
    DestroyInstance: std.meta.Child(c.PFN_vkDestroyInstance) = undefined,
    EnumerateDeviceExtensionProperties: std.meta.Child(c.PFN_vkEnumerateDeviceExtensionProperties) = undefined,
    EnumeratePhysicalDevices: std.meta.Child(c.PFN_vkEnumeratePhysicalDevices) = undefined,
    GetPhysicalDeviceFeatures2: std.meta.Child(c.PFN_vkGetPhysicalDeviceFeatures2) = undefined,
    GetPhysicalDeviceFormatProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceFormatProperties) = undefined,
    GetPhysicalDeviceImageFormatProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceImageFormatProperties) = undefined,
    GetPhysicalDeviceMemoryProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceMemoryProperties) = undefined,
    GetPhysicalDeviceProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceProperties) = undefined,
    GetPhysicalDeviceQueueFamilyProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties) = undefined,
    GetPhysicalDeviceSurfaceCapabilitiesKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR) = undefined,
    GetPhysicalDeviceSurfaceFormatsKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR) = undefined,
    GetPhysicalDeviceSurfacePresentModesKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR) = undefined,
    GetPhysicalDeviceSurfaceSupportKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR) = undefined,
};
const DebugExtDispatch = struct {
    CreateDebugUtilsMessengerEXT: std.meta.Child(c.PFN_vkCreateDebugUtilsMessengerEXT) = undefined,
    DestroyDebugUtilsMessengerEXT: std.meta.Child(c.PFN_vkDestroyDebugUtilsMessengerEXT) = undefined,
    SetDebugUtilsObjectNameEXT: std.meta.Child(c.PFN_vkSetDebugUtilsObjectNameEXT) = undefined,
    CmdBeginDebugUtilsLabelEXT: std.meta.Child(c.PFN_vkCmdBeginDebugUtilsLabelEXT) = undefined,
    CmdEndDebugUtilsLabelEXT: std.meta.Child(c.PFN_vkCmdEndDebugUtilsLabelEXT) = undefined,
    CmdInsertDebugUtilsLabelEXT: std.meta.Child(c.PFN_vkCmdInsertDebugUtilsLabelEXT) = undefined,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var handle: c.VkInstance = undefined;
pub var allocation_callbacks: ?*c.VkAllocationCallbacks = null;
pub var dispatch: Dispatch = undefined;
pub var debug_dispatch: ?DebugExtDispatch = null;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn validateExtensions(
    allocator: std.mem.Allocator,
    required_extensions: [][*:0]const u8,
) !void {
    const instance_extensions = try vk.library.enumerateInstanceExtensionPropertiesAlloc(
        allocator,
        null,
    );
    defer allocator.free(instance_extensions);

    for (required_extensions) |required_extension| {
        var found = false;
        for (instance_extensions) |instance_extension| {
            if (std.mem.eql(
                u8,
                std.mem.sliceTo(required_extension, 0),
                std.mem.sliceTo(&instance_extension.extensionName, 0),
            )) {
                found = true;
                break;
            }
        }
        if (!found) {
            vk.log.err(
                "Required instance extension not found: {s}",
                .{required_extension},
            );
            return error.RequiredInstanceExtensionNotFound;
        }
    }
}

fn validateLayers(
    allocator: std.mem.Allocator,
    required_layers: [][*:0]const u8,
) !void {
    const instance_layers = try vk.library.enumerateInstanceLayerPropertiesAlloc(
        allocator,
    );
    defer allocator.free(instance_layers);

    for (required_layers) |required_layer| {
        var found = false;
        for (instance_layers) |instance_layer| {
            if (std.mem.eql(
                u8,
                std.mem.sliceTo(required_layer, 0),
                std.mem.sliceTo(&instance_layer.layerName, 0),
            )) {
                found = true;
                break;
            }
        }
        if (!found) {
            vk.log.err(
                "Required instance layer not found: {s}",
                .{required_layer},
            );
            return error.RequiredInstanceLayerNotFound;
        }
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(options: *const gfx.Options) !void {
    var extensions = std.ArrayList([*:0]const u8).init(vk.arena);
    try extensions.append(c.VK_KHR_SURFACE_EXTENSION_NAME);
    switch (builtin.target.os.tag) {
        .windows => {
            try extensions.append(c.VK_KHR_WIN32_SURFACE_EXTENSION_NAME);
        },
        .linux => {
            if (platform.nativeWindowHandleType() == .wayland) {
                try extensions.append(c.VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME);
            } else {
                try extensions.append(c.VK_KHR_XCB_SURFACE_EXTENSION_NAME);
            }
        },
        .macos => {
            try extensions.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
            try extensions.append(c.VK_MVK_MACOS_SURFACE_EXTENSION_NAME);
        },
        else => {
            @compileError("Unsupported OS");
        },
    }

    if (options.enable_vulkan_debug) {
        try extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
    }

    try validateExtensions(vk.arena, extensions.items);

    const layers = try vk.prepareValidationLayers(vk.arena, options);
    try validateLayers(vk.arena, layers.items);

    const application_info = std.mem.zeroInit(
        c.VkApplicationInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "merlin",
            .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .pEngineName = "merlin",
            .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
            .apiVersion = c.VK_API_VERSION_1_3,
        },
    );

    var create_info = std.mem.zeroInit(
        c.VkInstanceCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .flags = switch (builtin.target.os.tag) {
                .macos, .ios, .tvos => c.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
                else => 0,
            },
            .pApplicationInfo = &application_info,
            .enabledLayerCount = @as(u32, @intCast(layers.items.len)),
            .ppEnabledLayerNames = layers.items.ptr,
            .enabledExtensionCount = @as(u32, @intCast(extensions.items.len)),
            .ppEnabledExtensionNames = extensions.items.ptr,
        },
    );

    vk.log.debug("Vulkan layers:", .{});
    for (layers.items) |layer| {
        vk.log.debug("  - {s}", .{layer});
    }
    vk.log.debug("Vulkan extensions:", .{});
    for (extensions.items) |extension| {
        vk.log.debug("  - {s}", .{extension});
    }

    if (options.enable_vulkan_debug) {
        const debug_create_info = std.mem.zeroInit(
            c.VkDebugUtilsMessengerCreateInfoEXT,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                .pfnUserCallback = @as(c.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&vk.debug.debugCallback)),
            },
        );
        create_info.pNext = &debug_create_info;
    }

    try vk.library.createInstance(
        &create_info,
        allocation_callbacks,
        &handle,
    );

    dispatch = try vk.library.load(Dispatch, handle);
    errdefer dispatch.DestroyInstance(handle, allocation_callbacks);

    debug_dispatch = null;
    if (options.enable_vulkan_debug) {
        debug_dispatch = try vk.library.load(DebugExtDispatch, handle);
    }
}

pub fn deinit() void {
    dispatch.DestroyInstance(handle, allocation_callbacks);
}

pub inline fn createDevice(
    physical_device: c.VkPhysicalDevice,
    create_info: *const c.VkDeviceCreateInfo,
    device: *c.VkDevice,
) !void {
    std.debug.assert(physical_device != null);

    try vk.checkVulkanError(
        "Failed to create Vulkan device",
        dispatch.CreateDevice(
            physical_device,
            create_info,
            allocation_callbacks,
            device,
        ),
    );
}
pub inline fn enumerateDeviceExtensionProperties(
    physical_device: c.VkPhysicalDevice,
    layer_name: [*c]const u8,
    count: *u32,
    properties: [*c]c.VkExtensionProperties,
) !void {
    std.debug.assert(physical_device != null);

    try vk.checkVulkanError(
        "Failed to enumerate Vulkan device extension properties",
        dispatch.EnumerateDeviceExtensionProperties(
            physical_device,
            layer_name,
            count,
            properties,
        ),
    );
}

pub fn enumerateDeviceExtensionPropertiesAlloc(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    layer_name: [*c]const u8,
) ![]c.VkExtensionProperties {
    std.debug.assert(physical_device != null);

    var count: u32 = undefined;
    try enumerateDeviceExtensionProperties(
        physical_device,
        layer_name,
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkExtensionProperties,
        count,
    );
    errdefer allocator.free(result);

    try enumerateDeviceExtensionProperties(
        physical_device,
        layer_name,
        &count,
        result.ptr,
    );
    return result;
}

pub inline fn enumeratePhysicalDevices(
    count: *u32,
    physical_devices: [*c]c.VkPhysicalDevice,
) !void {
    try vk.checkVulkanError(
        "Failed to enumerate Vulkan physical devices",
        dispatch.EnumeratePhysicalDevices(
            handle,
            count,
            physical_devices,
        ),
    );
}

pub fn enumeratePhysicalDevicesAlloc(allocator: std.mem.Allocator) ![]c.VkPhysicalDevice {
    var count: u32 = undefined;
    try enumeratePhysicalDevices(
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkPhysicalDevice,
        count,
    );
    errdefer allocator.free(result);

    try enumeratePhysicalDevices(
        &count,
        result.ptr,
    );
    return result;
}

pub inline fn getPhysicalDeviceFeatures2(
    physical_device: c.VkPhysicalDevice,
    features: *c.VkPhysicalDeviceFeatures2,
) void {
    std.debug.assert(physical_device != null);
    dispatch.GetPhysicalDeviceFeatures2(physical_device, features);
}

pub inline fn getPhysicalDeviceFormatProperties(
    physical_device: c.VkPhysicalDevice,
    format: c.VkFormat,
    format_properties: *c.VkFormatProperties,
) void {
    std.debug.assert(physical_device != null);
    dispatch.GetPhysicalDeviceFormatProperties(physical_device, format, format_properties);
}

pub inline fn getPhysicalDeviceImageFormatProperties(
    physical_device: c.VkPhysicalDevice,
    format: c.VkFormat,
    image_type: c.VkImageType,
    tiling: c.VkImageTiling,
    usage: c.VkImageUsageFlags,
    flags: c.VkImageCreateFlags,
    image_format_properties: *c.VkImageFormatProperties,
) !void {
    std.debug.assert(physical_device != null);

    try vk.checkVulkanError(
        "Failed to get physical device image format properties",
        dispatch.GetPhysicalDeviceImageFormatProperties(
            physical_device,
            format,
            image_type,
            tiling,
            usage,
            flags,
            image_format_properties,
        ),
    );
}

pub inline fn getPhysicalDeviceMemoryProperties(
    physical_device: c.VkPhysicalDevice,
    memory_properties: *c.VkPhysicalDeviceMemoryProperties,
) void {
    std.debug.assert(physical_device != null);
    dispatch.GetPhysicalDeviceMemoryProperties(physical_device, memory_properties);
}

pub inline fn getPhysicalDeviceProperties(
    physical_device: c.VkPhysicalDevice,
    properties: *c.VkPhysicalDeviceProperties,
) void {
    std.debug.assert(physical_device != null);
    dispatch.GetPhysicalDeviceProperties(physical_device, properties);
}

pub inline fn getPhysicalDeviceQueueFamilyProperties(
    physical_device: c.VkPhysicalDevice,
    count: *u32,
    queue_family_properties: [*c]c.VkQueueFamilyProperties,
) void {
    std.debug.assert(physical_device != null);
    dispatch.GetPhysicalDeviceQueueFamilyProperties(
        physical_device,
        count,
        queue_family_properties,
    );
}

pub fn getPhysicalDeviceQueueFamilyPropertiesAlloc(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
) ![]c.VkQueueFamilyProperties {
    std.debug.assert(physical_device != null);

    var count: u32 = undefined;
    getPhysicalDeviceQueueFamilyProperties(
        physical_device,
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkQueueFamilyProperties,
        count,
    );
    errdefer allocator.free(result);

    getPhysicalDeviceQueueFamilyProperties(
        physical_device,
        &count,
        result.ptr,
    );
    return result;
}

pub inline fn getPhysicalDeviceSurfaceCapabilitiesKHR(
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
    capabilities: *c.VkSurfaceCapabilitiesKHR,
) !void {
    std.debug.assert(physical_device != null);
    std.debug.assert(surface != null);

    try vk.checkVulkanError(
        "Failed to get physical device surface capabilities",
        dispatch.GetPhysicalDeviceSurfaceCapabilitiesKHR(
            physical_device,
            surface,
            capabilities,
        ),
    );
}

pub inline fn getPhysicalDeviceSurfaceFormatsKHR(
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
    count: *u32,
    formats: [*c]c.VkSurfaceFormatKHR,
) !void {
    std.debug.assert(physical_device != null);
    std.debug.assert(surface != null);

    try vk.checkVulkanError(
        "Failed to get physical device surface formats",
        dispatch.GetPhysicalDeviceSurfaceFormatsKHR(
            physical_device,
            surface,
            count,
            formats,
        ),
    );
}

pub inline fn getPhysicalDeviceSurfacePresentModesKHR(
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
    count: *u32,
    present_modes: [*c]c.VkPresentModeKHR,
) !void {
    std.debug.assert(physical_device != null);
    std.debug.assert(surface != null);

    try vk.checkVulkanError(
        "Failed to get physical device surface present modes",
        dispatch.GetPhysicalDeviceSurfacePresentModesKHR(
            physical_device,
            surface,
            count,
            present_modes,
        ),
    );
}

pub fn getPhysicalDeviceSurfacePresentModesKHRAlloc(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ![]c.VkPresentModeKHR {
    std.debug.assert(physical_device != null);
    std.debug.assert(surface != null);

    var count: u32 = undefined;
    try getPhysicalDeviceSurfacePresentModesKHR(
        physical_device,
        surface,
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkPresentModeKHR,
        count,
    );
    errdefer allocator.free(result);

    if (count > 0) {
        try getPhysicalDeviceSurfacePresentModesKHR(
            physical_device,
            surface,
            &count,
            result.ptr,
        );
    }

    return result;
}

pub inline fn getPhysicalDeviceSurfaceSupportKHR(
    physical_device: c.VkPhysicalDevice,
    queue_family_index: u32,
    surface: c.VkSurfaceKHR,
    supported: *c.VkBool32,
) !void {
    std.debug.assert(physical_device != null);
    std.debug.assert(surface != null);

    try vk.checkVulkanError(
        "Failed to get physical device surface support",
        dispatch.GetPhysicalDeviceSurfaceSupportKHR(
            physical_device,
            queue_family_index,
            surface,
            supported,
        ),
    );
}

pub fn getPhysicalDeviceSurfaceFormatsKHRAlloc(
    allocator: std.mem.Allocator,
    physical_device: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) ![]c.VkSurfaceFormatKHR {
    std.debug.assert(physical_device != null);
    std.debug.assert(surface != null);

    var count: u32 = undefined;
    try getPhysicalDeviceSurfaceFormatsKHR(
        physical_device,
        surface,
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkSurfaceFormatKHR,
        count,
    );
    errdefer allocator.free(result);

    if (count > 0) {
        try getPhysicalDeviceSurfaceFormatsKHR(
            physical_device,
            surface,
            &count,
            result.ptr,
        );
    }

    return result;
}

pub inline fn createDebugUtilsMessengerEXT(
    create_info: *const c.VkDebugUtilsMessengerCreateInfoEXT,
    messenger: *c.VkDebugUtilsMessengerEXT,
) !void {
    std.debug.assert(debug_dispatch != null);

    try vk.checkVulkanError(
        "Failed to create Vulkan debug messenger",
        debug_dispatch.?.CreateDebugUtilsMessengerEXT(
            handle,
            create_info,
            allocation_callbacks,
            messenger,
        ),
    );
}

pub inline fn destroyDebugUtilsMessengerEXT(messenger: c.VkDebugUtilsMessengerEXT) void {
    std.debug.assert(debug_dispatch != null);

    debug_dispatch.?.DestroyDebugUtilsMessengerEXT(
        handle,
        messenger,
        allocation_callbacks,
    );
}

pub inline fn setDebugUtilsObjectNameEXT(
    device: c.VkDevice,
    name_info: *const c.VkDebugUtilsObjectNameInfoEXT,
) !void {
    std.debug.assert(debug_dispatch != null);

    try vk.checkVulkanError(
        "Failed to set debug utils object name",
        debug_dispatch.?.SetDebugUtilsObjectNameEXT(
            device,
            name_info,
        ),
    );
}

pub inline fn cmdBeginDebugUtilsLabelEXT(
    command_buffer: c.VkCommandBuffer,
    label_info: *const c.VkDebugUtilsLabelEXT,
) void {
    std.debug.assert(debug_dispatch != null);

    debug_dispatch.?.CmdBeginDebugUtilsLabelEXT(
        command_buffer,
        label_info,
    );
}

pub inline fn cmdEndDebugUtilsLabelEXT(command_buffer: c.VkCommandBuffer) void {
    std.debug.assert(debug_dispatch != null);

    debug_dispatch.?.CmdEndDebugUtilsLabelEXT(command_buffer);
}

pub inline fn cmdInsertDebugUtilsLabelEXT(
    command_buffer: c.VkCommandBuffer,
    label_info: *const c.VkDebugUtilsLabelEXT,
) void {
    std.debug.assert(debug_dispatch != null);

    debug_dispatch.?.CmdInsertDebugUtilsLabelEXT(
        command_buffer,
        label_info,
    );
}
