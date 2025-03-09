const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Instance = struct {
    const Self = @This();
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
    };

    handle: c.VkInstance,
    allocation_callbacks: ?*c.VkAllocationCallbacks,
    dispatch: Dispatch,
    debug_dispatch: ?DebugExtDispatch,

    pub fn init(
        allocator: std.mem.Allocator,
        options: *const gfx.Options,
        library: *vk.Library,
        allocation_callbacks: ?*c.VkAllocationCallbacks,
    ) !Self {
        var extensions = std.ArrayList([*:0]const u8).init(allocator);
        defer extensions.deinit();

        try extensions.append(c.VK_KHR_SURFACE_EXTENSION_NAME);
        switch (builtin.target.os.tag) {
            .windows => {
                try extensions.append(c.VK_KHR_WIN32_SURFACE_EXTENSION_NAME);
            },
            .linux => {
                if (options.window_type == .wayland) {
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

        try validateExtensions(
            allocator,
            library,
            extensions.items,
        );

        var layers = try vk.prepareValidationLayers(
            allocator,
            options,
        );
        defer layers.deinit();

        try validateLayers(
            allocator,
            library,
            layers.items,
        );

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
                    .pfnUserCallback = @as(c.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&vk.debugCallback)),
                },
            );
            create_info.pNext = &debug_create_info;
        }

        var instance: c.VkInstance = undefined;
        try library.createInstance(
            &create_info,
            allocation_callbacks,
            &instance,
        );

        const dispatch = try library.load(Dispatch, instance);
        errdefer dispatch.DestroyInstance(instance, allocation_callbacks);

        var debug_dispatch: ?DebugExtDispatch = null;
        if (options.enable_vulkan_debug) {
            debug_dispatch = try library.load(DebugExtDispatch, instance);
        }

        return .{
            .handle = instance,
            .allocation_callbacks = allocation_callbacks,
            .dispatch = dispatch,
            .debug_dispatch = debug_dispatch,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatch.DestroyInstance(self.handle, self.allocation_callbacks);
    }

    fn validateExtensions(
        allocator: std.mem.Allocator,
        library: *vk.Library,
        required_extensions: [][*:0]const u8,
    ) !void {
        const instance_extensions = try library.enumerateInstanceExtensionPropertiesAlloc(
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
        library: *vk.Library,
        required_layers: [][*:0]const u8,
    ) !void {
        const instance_layers = try library.enumerateInstanceLayerPropertiesAlloc(
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
    // Dispatch functions
    // *********************************************************************************************

    pub fn createDevice(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        create_info: *const c.VkDeviceCreateInfo,
        device: *c.VkDevice,
    ) !void {
        std.debug.assert(physical_device != null);

        try vk.checkVulkanError(
            "Failed to create Vulkan device",
            self.dispatch.CreateDevice(
                physical_device,
                create_info,
                self.allocation_callbacks,
                device,
            ),
        );
    }
    pub fn enumerateDeviceExtensionProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        layer_name: [*c]const u8,
        count: *u32,
        properties: [*c]c.VkExtensionProperties,
    ) !void {
        std.debug.assert(physical_device != null);

        const result = self.dispatch.EnumerateDeviceExtensionProperties(
            physical_device,
            layer_name,
            count,
            properties,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            vk.log.warn("Failed to enumerate Vulkan device extension properties: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to enumerate Vulkan device extension properties",
                result,
            );
        }
    }

    pub fn enumerateDeviceExtensionPropertiesAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        layer_name: [*c]const u8,
    ) ![]c.VkExtensionProperties {
        std.debug.assert(physical_device != null);

        var count: u32 = undefined;
        try self.enumerateDeviceExtensionProperties(
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

        try self.enumerateDeviceExtensionProperties(
            physical_device,
            layer_name,
            &count,
            result.ptr,
        );
        return result;
    }

    pub fn enumeratePhysicalDevices(
        self: *const Self,
        count: *u32,
        physical_devices: [*c]c.VkPhysicalDevice,
    ) !void {
        const result = self.dispatch.EnumeratePhysicalDevices(
            self.handle,
            count,
            physical_devices,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            vk.log.warn("Failed to enumerate Vulkan physical devices: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to enumerate Vulkan physical devices",
                result,
            );
        }
    }

    pub fn enumeratePhysicalDevicesAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
    ) ![]c.VkPhysicalDevice {
        var count: u32 = undefined;
        try self.enumeratePhysicalDevices(
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.VkPhysicalDevice,
            count,
        );
        errdefer allocator.free(result);

        try self.enumeratePhysicalDevices(
            &count,
            result.ptr,
        );
        return result;
    }

    pub fn getPhysicalDeviceFeatures2(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        features: *c.VkPhysicalDeviceFeatures2,
    ) void {
        std.debug.assert(physical_device != null);
        self.dispatch.GetPhysicalDeviceFeatures2(physical_device, features);
    }

    pub fn getPhysicalDeviceFormatProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        format: c.VkFormat,
        format_properties: *c.VkFormatProperties,
    ) void {
        std.debug.assert(physical_device != null);
        self.dispatch.GetPhysicalDeviceFormatProperties(physical_device, format, format_properties);
    }

    pub fn getPhysicalDeviceImageFormatProperties(
        self: *const Self,
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
            self.dispatch.GetPhysicalDeviceImageFormatProperties(
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

    pub fn getPhysicalDeviceMemoryProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        memory_properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        std.debug.assert(physical_device != null);

        self.dispatch.GetPhysicalDeviceMemoryProperties(physical_device, memory_properties);
    }

    pub fn getPhysicalDeviceProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceProperties,
    ) void {
        std.debug.assert(physical_device != null);

        self.dispatch.GetPhysicalDeviceProperties(physical_device, properties);
    }

    pub fn getPhysicalDeviceQueueFamilyProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        count: *u32,
        queue_family_properties: [*c]c.VkQueueFamilyProperties,
    ) void {
        std.debug.assert(physical_device != null);

        self.dispatch.GetPhysicalDeviceQueueFamilyProperties(physical_device, count, queue_family_properties);
    }

    pub fn getPhysicalDeviceQueueFamilyPropertiesAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
    ) ![]c.VkQueueFamilyProperties {
        std.debug.assert(physical_device != null);

        var count: u32 = undefined;
        self.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);

        const result = try allocator.alloc(
            c.VkQueueFamilyProperties,
            count,
        );
        errdefer allocator.free(result);

        self.getPhysicalDeviceQueueFamilyProperties(
            physical_device,
            &count,
            result.ptr,
        );
        return result;
    }

    pub fn getPhysicalDeviceSurfaceCapabilitiesKHR(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        capabilities: *c.VkSurfaceCapabilitiesKHR,
    ) !void {
        std.debug.assert(physical_device != null);
        std.debug.assert(surface != null);

        try vk.checkVulkanError(
            "Failed to get physical device surface capabilities",
            self.dispatch.GetPhysicalDeviceSurfaceCapabilitiesKHR(
                physical_device,
                surface,
                capabilities,
            ),
        );
    }

    pub fn getPhysicalDeviceSurfaceFormatsKHR(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        count: *u32,
        formats: [*c]c.VkSurfaceFormatKHR,
    ) !void {
        std.debug.assert(physical_device != null);
        std.debug.assert(surface != null);

        const result = self.dispatch.GetPhysicalDeviceSurfaceFormatsKHR(
            physical_device,
            surface,
            count,
            formats,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            vk.log.warn("Failed to get physical device surface formats: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to get physical device surface formats",
                result,
            );
        }
    }

    pub fn getPhysicalDeviceSurfacePresentModesKHR(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        count: *u32,
        present_modes: [*c]c.VkPresentModeKHR,
    ) !void {
        std.debug.assert(physical_device != null);
        std.debug.assert(surface != null);

        const result = self.dispatch.GetPhysicalDeviceSurfacePresentModesKHR(
            physical_device,
            surface,
            count,
            present_modes,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            vk.log.warn("Failed to get physical device surface present modes: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to get physical device surface present modes",
                result,
            );
        }
    }

    pub fn getPhysicalDeviceSurfacePresentModesKHRAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) ![]c.VkPresentModeKHR {
        std.debug.assert(physical_device != null);
        std.debug.assert(surface != null);

        var count: u32 = undefined;
        try self.getPhysicalDeviceSurfacePresentModesKHR(
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
            try self.getPhysicalDeviceSurfacePresentModesKHR(
                physical_device,
                surface,
                &count,
                result.ptr,
            );
        }

        return result;
    }

    pub fn getPhysicalDeviceSurfaceSupportKHR(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        queue_family_index: u32,
        surface: c.VkSurfaceKHR,
        supported: *c.VkBool32,
    ) !void {
        std.debug.assert(physical_device != null);
        std.debug.assert(surface != null);

        try vk.checkVulkanError(
            "Failed to get physical device surface support",
            self.dispatch.GetPhysicalDeviceSurfaceSupportKHR(
                physical_device,
                queue_family_index,
                surface,
                supported,
            ),
        );
    }

    pub fn getPhysicalDeviceSurfaceFormatsKHRAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) ![]c.VkSurfaceFormatKHR {
        std.debug.assert(physical_device != null);
        std.debug.assert(surface != null);

        var count: u32 = undefined;
        try self.getPhysicalDeviceSurfaceFormatsKHR(
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
            try self.getPhysicalDeviceSurfaceFormatsKHR(
                physical_device,
                surface,
                &count,
                result.ptr,
            );
        }

        return result;
    }

    pub fn createDebugUtilsMessengerEXT(
        self: *const Self,
        create_info: *const c.VkDebugUtilsMessengerCreateInfoEXT,
        messenger: *c.VkDebugUtilsMessengerEXT,
    ) !void {
        std.debug.assert(self.debug_dispatch != null);

        try vk.checkVulkanError(
            "Failed to create Vulkan debug messenger",
            self.debug_dispatch.?.CreateDebugUtilsMessengerEXT(
                self.handle,
                create_info,
                self.allocation_callbacks,
                messenger,
            ),
        );
    }

    pub fn destroyDebugUtilsMessengerEXT(
        self: *const Self,
        messenger: c.VkDebugUtilsMessengerEXT,
    ) void {
        std.debug.assert(self.debug_dispatch != null);

        self.debug_dispatch.?.DestroyDebugUtilsMessengerEXT(
            self.handle,
            messenger,
            self.allocation_callbacks,
        );
    }
};
