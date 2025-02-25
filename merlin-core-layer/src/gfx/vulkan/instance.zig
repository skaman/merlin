const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Instance = struct {
    const Self = @This();
    const Dispatch = struct {
        DestroyInstance: std.meta.Child(c.PFN_vkDestroyInstance) = undefined,
        EnumeratePhysicalDevices: std.meta.Child(c.PFN_vkEnumeratePhysicalDevices) = undefined,
        GetPhysicalDeviceProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceProperties) = undefined,
        GetPhysicalDeviceFeatures: std.meta.Child(c.PFN_vkGetPhysicalDeviceFeatures) = undefined,
        GetPhysicalDeviceMemoryProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceMemoryProperties) = undefined,
        GetPhysicalDeviceQueueFamilyProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceQueueFamilyProperties) = undefined,
        GetPhysicalDeviceSurfaceSupportKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfaceSupportKHR) = undefined,
        GetPhysicalDeviceSurfaceCapabilitiesKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR) = undefined,
        GetPhysicalDeviceSurfaceFormatsKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfaceFormatsKHR) = undefined,
        GetPhysicalDeviceSurfacePresentModesKHR: std.meta.Child(c.PFN_vkGetPhysicalDeviceSurfacePresentModesKHR) = undefined,
        EnumerateDeviceExtensionProperties: std.meta.Child(c.PFN_vkEnumerateDeviceExtensionProperties) = undefined,
        CreateDebugUtilsMessengerEXT: std.meta.Child(c.PFN_vkCreateDebugUtilsMessengerEXT) = undefined,
        DestroyDebugUtilsMessengerEXT: std.meta.Child(c.PFN_vkDestroyDebugUtilsMessengerEXT) = undefined,
        CreateDevice: std.meta.Child(c.PFN_vkCreateDevice) = undefined,
    };

    handle: c.VkInstance,
    allocation_callbacks: ?*c.VkAllocationCallbacks,
    dispatch: Dispatch,

    pub fn init(
        allocator: std.mem.Allocator,
        options: *const gfx.GraphicsOptions,
        library: *vk.Library,
        allocation_callbacks: ?*c.VkAllocationCallbacks,
    ) !Self {
        var extensions = std.ArrayList([*:0]const u8).init(allocator);
        defer extensions.deinit();

        var glfw_extension_count: u32 = 0;
        const glfw_extensions = c.glfwGetRequiredInstanceExtensions(
            &glfw_extension_count,
        );
        for (0..glfw_extension_count) |index| {
            try extensions.append(glfw_extensions[index]);
        }

        switch (builtin.target.os.tag) {
            .macos, .ios, .tvos => {
                try extensions.append(c.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
            },
            else => {},
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
                .pApplicationName = "z3dfx",
                .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
                .pEngineName = "z3dfx",
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

        return .{
            .handle = instance,
            .allocation_callbacks = allocation_callbacks,
            .dispatch = try library.load(Dispatch, instance),
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

    pub fn enumeratePhysicalDevices(
        self: *Self,
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

    pub fn enumeratePhysicalDevicesAlloc(self: *Self, allocator: std.mem.Allocator) ![]c.VkPhysicalDevice {
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

    pub fn getPhysicalDeviceProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceProperties(physical_device, properties);
    }

    pub fn getPhysicalDeviceFeatures(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        features: *c.VkPhysicalDeviceFeatures,
    ) void {
        self.dispatch.GetPhysicalDeviceFeatures(physical_device, features);
    }

    pub fn getPhysicalDeviceMemoryProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        memory_properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceMemoryProperties(physical_device, memory_properties);
    }

    pub fn getPhysicalDeviceQueueFamilyProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        count: *u32,
        queue_family_properties: [*c]c.VkQueueFamilyProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceQueueFamilyProperties(physical_device, count, queue_family_properties);
    }

    pub fn getPhysicalDeviceQueueFamilyPropertiesAlloc(
        self: *Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
    ) ![]c.VkQueueFamilyProperties {
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

    pub fn getPhysicalDeviceSurfaceSupportKHR(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        queue_family_index: u32,
        surface: c.VkSurfaceKHR,
        supported: *c.VkBool32,
    ) !void {
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

    pub fn getPhysicalDeviceSurfaceCapabilitiesKHR(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        capabilities: *c.VkSurfaceCapabilitiesKHR,
    ) !void {
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
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        count: *u32,
        formats: [*c]c.VkSurfaceFormatKHR,
    ) !void {
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

    pub fn getPhysicalDeviceSurfaceFormatsKHRAlloc(
        self: *Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) ![]c.VkSurfaceFormatKHR {
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

    pub fn getPhysicalDeviceSurfacePresentModesKHR(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        count: *u32,
        present_modes: [*c]c.VkPresentModeKHR,
    ) !void {
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
        self: *Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) ![]c.VkPresentModeKHR {
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

    pub fn enumerateDeviceExtensionProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        layer_name: [*c]const u8,
        count: *u32,
        properties: [*c]c.VkExtensionProperties,
    ) !void {
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
        self: *Self,
        allocator: std.mem.Allocator,
        physical_device: c.VkPhysicalDevice,
        layer_name: [*c]const u8,
    ) ![]c.VkExtensionProperties {
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

    pub fn createDebugUtilsMessengerEXT(
        self: *Self,
        create_info: *const c.VkDebugUtilsMessengerCreateInfoEXT,
        messenger: *c.VkDebugUtilsMessengerEXT,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan debug messenger",
            self.dispatch.CreateDebugUtilsMessengerEXT(
                self.handle,
                create_info,
                self.allocation_callbacks,
                messenger,
            ),
        );
    }

    pub fn destroyDebugUtilsMessengerEXT(
        self: *Self,
        messenger: c.VkDebugUtilsMessengerEXT,
    ) void {
        self.dispatch.DestroyDebugUtilsMessengerEXT(
            self.handle,
            messenger,
            self.allocation_callbacks,
        );
    }

    pub fn createDevice(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        create_info: *const c.VkDeviceCreateInfo,
        device: *c.VkDevice,
    ) !void {
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
};
