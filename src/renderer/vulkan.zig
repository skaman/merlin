const std = @import("std");
const builtin = @import("builtin");

const c = @import("../c.zig").c;
const z3dfx = @import("z3dfx.zig");

fn logErr(
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.err("[z3dfx][vk] " ++ format, args);
}

fn logWarn(
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.warn("[z3dfx][vk] " ++ format, args);
}

fn logInfo(
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.info("[z3dfx][vk] " ++ format, args);
}

fn logDebug(
    comptime format: []const u8,
    args: anytype,
) void {
    std.log.debug("[z3dfx][vk] " ++ format, args);
}

fn debugCallback(
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
        logErr("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        logWarn("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
        logInfo("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) {
        logDebug("{s}", .{p_callback_data.*.pMessage});
    }

    return c.VK_FALSE;
}

fn getPhysicalDeviceTypeLabel(device_type: c.VkPhysicalDeviceType) []const u8 {
    return switch (device_type) {
        c.VK_PHYSICAL_DEVICE_TYPE_OTHER => "Other",
        c.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
        c.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
        else => unreachable,
    };
}

fn prepareValidationLayers(
    allocator: std.mem.Allocator,
    options: *const z3dfx.GraphicsOptions,
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

fn checkVulkanError(comptime message: []const u8, result: c.VkResult) !void {
    return switch (result) {
        c.VK_SUCCESS => {},
        c.VK_ERROR_OUT_OF_HOST_MEMORY => {
            logErr("{s}: out of host memory", .{message});
            return error.VulkanOutOfHostMemory;
        },
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => {
            logErr("{s}: out of device memory", .{message});
            return error.VulkanOutOfDeviceMemory;
        },
        c.VK_ERROR_INITIALIZATION_FAILED => {
            logErr("{s}: initialization failed", .{message});
            return error.VulkanInitializationFailed;
        },
        c.VK_ERROR_LAYER_NOT_PRESENT => {
            logErr("{s}: layer not present", .{message});
            return error.VulkanLayerNotPresent;
        },
        c.VK_ERROR_EXTENSION_NOT_PRESENT => {
            logErr("{s}: extension not present", .{message});
            return error.VulkanExtensionNotPresent;
        },
        c.VK_ERROR_FEATURE_NOT_PRESENT => {
            logErr("{s}: feature not present", .{message});
            return error.VulkanFeatureNotPresent;
        },
        c.VK_ERROR_INCOMPATIBLE_DRIVER => {
            logErr("{s}: incompatible driver", .{message});
            return error.VulkanIncompatibleDriver;
        },
        c.VK_ERROR_TOO_MANY_OBJECTS => {
            logErr("{s}: too many objects", .{message});
            return error.VulkanTooManyObjects;
        },
        c.VK_ERROR_DEVICE_LOST => {
            logErr("{s}: device lost", .{message});
            return error.VulkanDeviceLost;
        },
        c.VK_ERROR_SURFACE_LOST_KHR => {
            logErr("{s}: surface lost", .{message});
            return error.VulkanSurfaceLost;
        },
        c.VK_ERROR_NATIVE_WINDOW_IN_USE_KHR => {
            logErr("{s}: native window in use", .{message});
            return error.VulkanNativeWindowInUse;
        },
        c.VK_ERROR_COMPRESSION_EXHAUSTED_EXT => {
            logErr("{s}: compression exhausted", .{message});
            return error.VulkanCompressionExhausted;
        },
        c.VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS_KHR => {
            logErr("{s}: invalid opaque capture address", .{message});
            return error.VulkanInvalidOpaqueCaptureAddress;
        },
        c.VK_ERROR_INVALID_SHADER_NV => {
            logErr("{s}: invalid shader", .{message});
            return error.VulkanInvalidShader;
        },
        else => {
            logErr("{s}: {d}", .{ message, result });
            return error.VulkanUnknownError;
        },
    };
}

const MaxFramesInFlight = 2;

const VulkanLibrary = struct {
    const Self = @This();
    const LibraryNames = switch (builtin.os.tag) {
        .windows => &[_][]const u8{"vulkan-1.dll"},
        .ios, .macos, .tvos, .watchos => &[_][]const u8{ "libvulkan.dylib", "libvulkan.1.dylib", "libMoltenVK.dylib" },
        else => &[_][]const u8{ "libvulkan.so.1", "libvulkan.so" },
    };
    const Dispatch = struct {
        CreateInstance: std.meta.Child(c.PFN_vkCreateInstance) = undefined,
        EnumerateInstanceExtensionProperties: std.meta.Child(c.PFN_vkEnumerateInstanceExtensionProperties) = undefined,
        EnumerateInstanceLayerProperties: std.meta.Child(c.PFN_vkEnumerateInstanceLayerProperties) = undefined,
    };

    handle: std.DynLib,
    get_instance_proc_addr: std.meta.Child(c.PFN_vkGetInstanceProcAddr),
    dispatch: Dispatch,

    fn init() !Self {
        var library = try loadLibrary();
        const get_instance_proc_addr = library.lookup(
            std.meta.Child(c.PFN_vkGetInstanceProcAddr),
            "vkGetInstanceProcAddr",
        ) orelse {
            logErr("Failed to load vkGetInstanceProcAddr", .{});
            return error.GetInstanceProcAddrNotFound;
        };

        var self: Self = .{
            .handle = library,
            .get_instance_proc_addr = get_instance_proc_addr,
            .dispatch = undefined,
        };
        self.dispatch = try self.load(Dispatch, null);
        return self;
    }

    fn deinit(self: *Self) void {
        self.handle.close();
    }

    fn loadLibrary() !std.DynLib {
        for (LibraryNames) |library_name| {
            return std.DynLib.open(library_name) catch continue;
        }
        logErr("Failed to load Vulkan library", .{});
        return error.LoadLibraryFailed;
    }

    fn get_proc(
        self: Self,
        comptime PFN: type,
        instance: c.VkInstance,
        name: [*c]const u8,
    ) !std.meta.Child(PFN) {
        if (self.get_instance_proc_addr(instance, name)) |proc| {
            return @ptrCast(proc);
        } else {
            logErr("Failed to load Vulkan proc: {s}", .{name});
            return error.GetInstanceProcAddrFailed;
        }
    }

    fn load(
        self: VulkanLibrary,
        comptime TDispatch: type,
        instance: c.VkInstance,
    ) !TDispatch {
        var dispatch = TDispatch{};
        inline for (@typeInfo(TDispatch).@"struct".fields) |field| {
            @field(dispatch, field.name) = try self.get_proc(
                ?field.type,
                instance,
                "vk" ++ field.name,
            );
        }
        return dispatch;
    }

    fn createInstance(
        self: *Self,
        create_info: *const c.VkInstanceCreateInfo,
        allocation_callbacks: ?*const c.VkAllocationCallbacks,
        instance: *c.VkInstance,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan instance",
            self.dispatch.CreateInstance(create_info, allocation_callbacks, instance),
        );
    }

    fn enumerateInstanceExtensionProperties(
        self: *Self,
        layer_name: [*c]const u8,
        count: *u32,
        properties: [*c]c.VkExtensionProperties,
    ) !void {
        const result = self.dispatch.EnumerateInstanceExtensionProperties(
            layer_name,
            count,
            properties,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            logWarn("Failed to enumerate Vulkan instance extension properties: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to enumerate Vulkan instance extension properties",
                result,
            );
        }
    }

    fn enumerateInstanceExtensionPropertiesAlloc(
        self: *Self,
        allocator: std.mem.Allocator,
        layer_name: [*c]const u8,
    ) ![]c.VkExtensionProperties {
        var count: u32 = undefined;
        try self.enumerateInstanceExtensionProperties(
            layer_name,
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.VkExtensionProperties,
            count,
        );
        errdefer allocator.free(result);

        try self.enumerateInstanceExtensionProperties(
            layer_name,
            &count,
            result.ptr,
        );
        return result;
    }

    fn enumerateInstanceLayerProperties(
        self: *Self,
        count: *u32,
        properties: [*c]c.VkLayerProperties,
    ) !void {
        const result = self.dispatch.EnumerateInstanceLayerProperties(
            count,
            properties,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            logWarn("Failed to enumerate Vulkan instance layer properties: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to enumerate Vulkan instance layer properties",
                result,
            );
        }
    }

    fn enumerateInstanceLayerPropertiesAlloc(
        self: *Self,
        allocator: std.mem.Allocator,
    ) ![]c.VkLayerProperties {
        var count: u32 = undefined;
        try self.enumerateInstanceLayerProperties(
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.VkLayerProperties,
            count,
        );
        errdefer allocator.free(result);

        try self.enumerateInstanceLayerProperties(
            &count,
            result.ptr,
        );
        return result;
    }
};

const VulkanInstance = struct {
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

    fn init(
        graphics_ctx: *const z3dfx.GraphicsContext,
        vulkan_library: *VulkanLibrary,
        allocation_callbacks: ?*c.VkAllocationCallbacks,
    ) !Self {
        var extensions = std.ArrayList([*:0]const u8).init(
            graphics_ctx.allocator,
        );
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

        if (graphics_ctx.options.enable_vulkan_debug) {
            try extensions.append(c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        }

        try validateExtensions(
            graphics_ctx.allocator,
            vulkan_library,
            extensions.items,
        );

        var layers = try prepareValidationLayers(
            graphics_ctx.allocator,
            &graphics_ctx.options,
        );
        defer layers.deinit();

        try validateLayers(
            graphics_ctx.allocator,
            vulkan_library,
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

        if (graphics_ctx.options.enable_vulkan_debug) {
            const debug_create_info = std.mem.zeroInit(
                c.VkDebugUtilsMessengerCreateInfoEXT,
                .{
                    .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                    .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                    .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                    .pfnUserCallback = @as(c.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&debugCallback)),
                },
            );
            create_info.pNext = &debug_create_info;
        }

        var instance: c.VkInstance = undefined;
        try vulkan_library.createInstance(
            &create_info,
            allocation_callbacks,
            &instance,
        );

        return .{
            .handle = instance,
            .allocation_callbacks = allocation_callbacks,
            .dispatch = try vulkan_library.load(Dispatch, instance),
        };
    }

    fn deinit(self: *Self) void {
        self.dispatch.DestroyInstance(self.handle, self.allocation_callbacks);
    }

    fn validateExtensions(
        allocator: std.mem.Allocator,
        vulkan_library: *VulkanLibrary,
        required_extensions: [][*:0]const u8,
    ) !void {
        const instance_extensions = try vulkan_library.enumerateInstanceExtensionPropertiesAlloc(
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
                logErr(
                    "Required instance extension not found: {s}",
                    .{required_extension},
                );
                return error.RequiredInstanceExtensionNotFound;
            }
        }
    }

    fn validateLayers(
        allocator: std.mem.Allocator,
        vulkan_library: *VulkanLibrary,
        required_layers: [][*:0]const u8,
    ) !void {
        const instance_layers = try vulkan_library.enumerateInstanceLayerPropertiesAlloc(
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
                logErr(
                    "Required instance layer not found: {s}",
                    .{required_layer},
                );
                return error.RequiredInstanceLayerNotFound;
            }
        }
    }

    fn enumeratePhysicalDevices(
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
            logWarn("Failed to enumerate Vulkan physical devices: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to enumerate Vulkan physical devices",
                result,
            );
        }
    }

    fn enumeratePhysicalDevicesAlloc(self: *Self, allocator: std.mem.Allocator) ![]c.VkPhysicalDevice {
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

    fn getPhysicalDeviceProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        properties: *c.VkPhysicalDeviceProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceProperties(physical_device, properties);
    }

    fn getPhysicalDeviceFeatures(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        features: *c.VkPhysicalDeviceFeatures,
    ) void {
        self.dispatch.GetPhysicalDeviceFeatures(physical_device, features);
    }

    fn getPhysicalDeviceMemoryProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        memory_properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceMemoryProperties(physical_device, memory_properties);
    }

    fn getPhysicalDeviceQueueFamilyProperties(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        count: *u32,
        queue_family_properties: [*c]c.VkQueueFamilyProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceQueueFamilyProperties(physical_device, count, queue_family_properties);
    }

    fn getPhysicalDeviceQueueFamilyPropertiesAlloc(
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

    fn getPhysicalDeviceSurfaceSupportKHR(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        queue_family_index: u32,
        surface: c.VkSurfaceKHR,
        supported: *c.VkBool32,
    ) !void {
        try checkVulkanError(
            "Failed to get physical device surface support",
            self.dispatch.GetPhysicalDeviceSurfaceSupportKHR(
                physical_device,
                queue_family_index,
                surface,
                supported,
            ),
        );
    }

    fn getPhysicalDeviceSurfaceCapabilitiesKHR(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
        capabilities: *c.VkSurfaceCapabilitiesKHR,
    ) !void {
        try checkVulkanError(
            "Failed to get physical device surface capabilities",
            self.dispatch.GetPhysicalDeviceSurfaceCapabilitiesKHR(
                physical_device,
                surface,
                capabilities,
            ),
        );
    }

    fn getPhysicalDeviceSurfaceFormatsKHR(
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
            logWarn("Failed to get physical device surface formats: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to get physical device surface formats",
                result,
            );
        }
    }

    fn getPhysicalDeviceSurfaceFormatsKHRAlloc(
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

    fn getPhysicalDeviceSurfacePresentModesKHR(
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
            logWarn("Failed to get physical device surface present modes: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to get physical device surface present modes",
                result,
            );
        }
    }

    fn getPhysicalDeviceSurfacePresentModesKHRAlloc(
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

    fn enumerateDeviceExtensionProperties(
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
            logWarn("Failed to enumerate Vulkan device extension properties: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to enumerate Vulkan device extension properties",
                result,
            );
        }
    }

    fn enumerateDeviceExtensionPropertiesAlloc(
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

    fn createDebugUtilsMessengerEXT(
        self: *Self,
        create_info: *const c.VkDebugUtilsMessengerCreateInfoEXT,
        messenger: *c.VkDebugUtilsMessengerEXT,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan debug messenger",
            self.dispatch.CreateDebugUtilsMessengerEXT(
                self.handle,
                create_info,
                self.allocation_callbacks,
                messenger,
            ),
        );
    }

    fn destroyDebugUtilsMessengerEXT(
        self: *Self,
        messenger: c.VkDebugUtilsMessengerEXT,
    ) void {
        self.dispatch.DestroyDebugUtilsMessengerEXT(
            self.handle,
            messenger,
            self.allocation_callbacks,
        );
    }

    fn createDevice(
        self: *Self,
        physical_device: c.VkPhysicalDevice,
        create_info: *const c.VkDeviceCreateInfo,
        device: *c.VkDevice,
    ) !void {
        try checkVulkanError(
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

const VulkanDevice = struct {
    const Self = @This();
    const Dispatch = struct {
        DestroyDevice: std.meta.Child(c.PFN_vkDestroyDevice) = undefined,
        GetDeviceQueue: std.meta.Child(c.PFN_vkGetDeviceQueue) = undefined,
        QueueSubmit: std.meta.Child(c.PFN_vkQueueSubmit) = undefined,
        QueuePresentKHR: std.meta.Child(c.PFN_vkQueuePresentKHR) = undefined,
        CreateSwapchainKHR: std.meta.Child(c.PFN_vkCreateSwapchainKHR) = undefined,
        DestroySwapchainKHR: std.meta.Child(c.PFN_vkDestroySwapchainKHR) = undefined,
        GetSwapchainImagesKHR: std.meta.Child(c.PFN_vkGetSwapchainImagesKHR) = undefined,
        CreateImageView: std.meta.Child(c.PFN_vkCreateImageView) = undefined,
        DestroyImageView: std.meta.Child(c.PFN_vkDestroyImageView) = undefined,
        CreateShaderModule: std.meta.Child(c.PFN_vkCreateShaderModule) = undefined,
        DestroyShaderModule: std.meta.Child(c.PFN_vkDestroyShaderModule) = undefined,
        CreateGraphicsPipelines: std.meta.Child(c.PFN_vkCreateGraphicsPipelines) = undefined,
        DestroyPipeline: std.meta.Child(c.PFN_vkDestroyPipeline) = undefined,
        CreatePipelineLayout: std.meta.Child(c.PFN_vkCreatePipelineLayout) = undefined,
        DestroyPipelineLayout: std.meta.Child(c.PFN_vkDestroyPipelineLayout) = undefined,
        CreateRenderPass: std.meta.Child(c.PFN_vkCreateRenderPass) = undefined,
        DestroyRenderPass: std.meta.Child(c.PFN_vkDestroyRenderPass) = undefined,
        CreateFramebuffer: std.meta.Child(c.PFN_vkCreateFramebuffer) = undefined,
        DestroyFramebuffer: std.meta.Child(c.PFN_vkDestroyFramebuffer) = undefined,
        CreateCommandPool: std.meta.Child(c.PFN_vkCreateCommandPool) = undefined,
        DestroyCommandPool: std.meta.Child(c.PFN_vkDestroyCommandPool) = undefined,
        AllocateCommandBuffers: std.meta.Child(c.PFN_vkAllocateCommandBuffers) = undefined,
        CreateSemaphore: std.meta.Child(c.PFN_vkCreateSemaphore) = undefined,
        DestroySemaphore: std.meta.Child(c.PFN_vkDestroySemaphore) = undefined,
        CreateFence: std.meta.Child(c.PFN_vkCreateFence) = undefined,
        DestroyFence: std.meta.Child(c.PFN_vkDestroyFence) = undefined,
        WaitForFences: std.meta.Child(c.PFN_vkWaitForFences) = undefined,
        ResetFences: std.meta.Child(c.PFN_vkResetFences) = undefined,
        AcquireNextImageKHR: std.meta.Child(c.PFN_vkAcquireNextImageKHR) = undefined,
        DeviceWaitIdle: std.meta.Child(c.PFN_vkDeviceWaitIdle) = undefined,
    };
    const QueueFamilyIndices = struct {
        graphics_family: ?u32 = null,
        present_family: ?u32 = null,

        fn isComplete(self: QueueFamilyIndices) bool {
            return self.graphics_family != null and self.present_family != null;
        }
    };

    instance: *const VulkanInstance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    dispatch: Dispatch,
    queue_family_indices: QueueFamilyIndices,

    fn init(
        graphics_ctx: *const z3dfx.GraphicsContext,
        vulkan_library: *VulkanLibrary,
        instance: *VulkanInstance,
        surface: *const VulkanSurface,
    ) !Self {
        const physical_devices = try instance.enumeratePhysicalDevicesAlloc(
            graphics_ctx.allocator,
        );
        defer graphics_ctx.allocator.free(physical_devices);

        if (physical_devices.len == 0) {
            logErr("No Vulkan physical devices found", .{});
            return error.NoPhysicalDevicesFound;
        }

        const device_required_extensions = [_][*:0]const u8{
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        var selected_physical_device: c.VkPhysicalDevice = null;
        var selected_physical_device_score: u32 = 0;
        var selected_physical_device_index: usize = 0;
        var selected_physical_device_properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
        for (physical_devices, 0..) |physical_device, index| {
            const score = try rateDeviceSuitability(
                graphics_ctx.allocator,
                instance,
                surface,
                physical_device,
                &device_required_extensions,
            );

            var properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
            instance.getPhysicalDeviceProperties(physical_device, &properties);

            logDebug("---------------------------------------------------------------", .{});
            logDebug("  Physical device: {d}", .{index});
            logDebug("             Name: {s}", .{properties.deviceName});
            logDebug("      API version: {d}.{d}.{d}", .{
                c.VK_API_VERSION_MAJOR(properties.apiVersion),
                c.VK_API_VERSION_MINOR(properties.apiVersion),
                c.VK_API_VERSION_PATCH(properties.apiVersion),
            });
            logDebug("      API variant: {d}", .{
                c.VK_API_VERSION_VARIANT(properties.apiVersion),
            });
            logDebug("   Driver version: {x}", .{properties.driverVersion});
            logDebug("        Vendor ID: {x}", .{properties.vendorID});
            logDebug("        Device ID: {x}", .{properties.deviceID});
            logDebug("             Type: {s}", .{getPhysicalDeviceTypeLabel(properties.deviceType)});
            logDebug("            Score: {d}", .{score});

            var memory_properties = std.mem.zeroes(
                c.VkPhysicalDeviceMemoryProperties,
            );
            instance.getPhysicalDeviceMemoryProperties(
                physical_device,
                &memory_properties,
            );

            logDebug("Memory type count: {d}", .{memory_properties.memoryTypeCount});
            for (0..memory_properties.memoryTypeCount) |mp_index| {
                const memory_type = memory_properties.memoryTypes[mp_index];
                logDebug(
                    "              {d:0>3}: flags 0x{x:0>8}, index {d}",
                    .{ mp_index, memory_type.propertyFlags, memory_type.heapIndex },
                );
            }
            logDebug("Memory heap count: {d}", .{memory_properties.memoryHeapCount});
            for (0..memory_properties.memoryHeapCount) |mh_index| {
                const memory_heap = memory_properties.memoryHeaps[mh_index];
                logDebug(
                    "              {d:0>3}: size {d}, flags 0x{x:0>8}",
                    .{ mh_index, std.fmt.fmtIntSizeBin(memory_heap.size), memory_heap.flags },
                );
            }

            if (selected_physical_device == null or score > selected_physical_device_score) {
                selected_physical_device = physical_device;
                selected_physical_device_score = score;
                selected_physical_device_index = index;
                selected_physical_device_properties = properties;
            }
        }

        if (selected_physical_device == null) {
            logErr("No suitable Vulkan physical devices found", .{});
            return error.NoSuitablePhysicalDevicesFound;
        }

        logDebug("---------------------------------------------------------------", .{});
        logDebug(
            "Using physical device {d}: {s}",
            .{ selected_physical_device_index, selected_physical_device_properties.deviceName },
        );

        const queue_family_indices = try findQueueFamilies(
            graphics_ctx.allocator,
            instance,
            surface,
            selected_physical_device,
        );

        var unique_queue_families = std.ArrayList(u32).init(
            graphics_ctx.allocator,
        );
        defer unique_queue_families.deinit();
        try unique_queue_families.append(queue_family_indices.graphics_family.?);
        if (queue_family_indices.present_family != queue_family_indices.graphics_family) {
            try unique_queue_families.append(queue_family_indices.present_family.?);
        }

        var device_queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(
            graphics_ctx.allocator,
        );
        defer device_queue_create_infos.deinit();

        const queue_priorities = [_]f32{1.0};
        for (unique_queue_families.items) |queue_family| {
            const device_queue_create_info = std.mem.zeroInit(
                c.VkDeviceQueueCreateInfo,
                .{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                    .queueFamilyIndex = queue_family,
                    .queueCount = queue_priorities.len,
                    .pQueuePriorities = &queue_priorities,
                },
            );
            try device_queue_create_infos.append(device_queue_create_info);
        }
        const physical_device_features = std.mem.zeroInit(
            c.VkPhysicalDeviceFeatures,
            .{},
        );

        const validation_layers = try prepareValidationLayers(
            graphics_ctx.allocator,
            &graphics_ctx.options,
        );
        defer validation_layers.deinit();

        const device_create_info = std.mem.zeroInit(
            c.VkDeviceCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .queueCreateInfoCount = @as(u32, @intCast(device_queue_create_infos.items.len)),
                .pQueueCreateInfos = device_queue_create_infos.items.ptr,
                .enabledLayerCount = @as(u32, @intCast(validation_layers.items.len)),
                .ppEnabledLayerNames = validation_layers.items.ptr,
                .enabledExtensionCount = @as(u32, @intCast(device_required_extensions.len)),
                .ppEnabledExtensionNames = &device_required_extensions,
                .pEnabledFeatures = &physical_device_features,
            },
        );

        var device: c.VkDevice = undefined;
        try instance.createDevice(
            selected_physical_device,
            &device_create_info,
            &device,
        );

        return .{
            .instance = instance,
            .physical_device = selected_physical_device,
            .device = device,
            .dispatch = try vulkan_library.load(Dispatch, instance.handle),
            .queue_family_indices = queue_family_indices,
        };
    }

    fn deinit(self: *Self) void {
        self.dispatch.DestroyDevice(
            self.device,
            self.instance.allocation_callbacks,
        );
    }

    fn rateDeviceSuitability(
        allocator: std.mem.Allocator,
        instance: *VulkanInstance,
        surface: *const VulkanSurface,
        physical_device: c.VkPhysicalDevice,
        required_extensions: []const [*:0]const u8,
    ) !u32 {
        var properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
        var features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
        var queue_family_properties = std.ArrayList(c.VkQueueFamilyProperties).init(
            allocator,
        );
        defer queue_family_properties.deinit();

        var score: u32 = 0;

        // Device properties
        instance.getPhysicalDeviceProperties(
            physical_device,
            &properties,
        );
        if (properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            score += 1000;
        }
        score += properties.limits.maxImageDimension2D;

        // Queue families
        const queue_family_indices = try findQueueFamilies(
            allocator,
            instance,
            surface,
            physical_device,
        );

        // Device features
        instance.getPhysicalDeviceFeatures(
            physical_device,
            &features,
        );

        const device_extension_support = try checkDeviceExtensionSupport(
            allocator,
            instance,
            physical_device,
            required_extensions,
        );

        var swap_chain_support = try SwapChainSupportDetails.init(
            allocator,
            instance,
            physical_device,
            surface.handle,
        );
        defer swap_chain_support.deinit();

        const swap_chain_adequate = (swap_chain_support.formats.len > 0 and
            swap_chain_support.present_modes.len > 0);

        if (features.geometryShader == 0 or
            !queue_family_indices.isComplete() or
            !device_extension_support or
            !swap_chain_adequate)
        {
            return 0;
        }

        return score;
    }

    fn findQueueFamilies(
        allocator: std.mem.Allocator,
        instance: *VulkanInstance,
        surface: *const VulkanSurface,
        physical_device: c.VkPhysicalDevice,
    ) !QueueFamilyIndices {
        var queue_family_indices = QueueFamilyIndices{};

        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
            allocator,
            physical_device,
        );
        defer allocator.free(queue_families);

        for (queue_families, 0..) |queue_family, index| {
            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                queue_family_indices.graphics_family = @intCast(index);
            }

            var present_support: c.VkBool32 = 0;
            try instance.getPhysicalDeviceSurfaceSupportKHR(
                physical_device,
                @intCast(index),
                surface.handle,
                &present_support,
            );
            if (present_support != 0) {
                queue_family_indices.present_family = @intCast(index);
            }

            if (queue_family_indices.isComplete()) {
                break;
            }
        }

        return queue_family_indices;
    }

    fn checkDeviceExtensionSupport(
        allocator: std.mem.Allocator,
        instance: *VulkanInstance,
        physical_device: c.VkPhysicalDevice,
        required_extensions: []const [*:0]const u8,
    ) !bool {
        const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(
            allocator,
            physical_device,
            null,
        );
        defer allocator.free(available_extensions);

        for (required_extensions) |required_extension| {
            var found = false;
            for (available_extensions) |available_extension| {
                if (std.mem.eql(
                    u8,
                    std.mem.sliceTo(required_extension, 0),
                    std.mem.sliceTo(&available_extension.extensionName, 0),
                )) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                logErr(
                    "Required device extension not found: {s}",
                    .{required_extension},
                );
                return false;
            }
        }

        return true;
    }

    fn getDeviceQueue(
        self: *const Self,
        queue_family_index: u32,
        queue_index: u32,
        queue: *c.VkQueue,
    ) void {
        self.dispatch.GetDeviceQueue(
            self.device,
            queue_family_index,
            queue_index,
            queue,
        );
    }

    fn queueSubmit(
        self: *const Self,
        queue: c.VkQueue,
        submit_count: u32,
        submits: [*c]const c.VkSubmitInfo,
        fence: c.VkFence,
    ) !void {
        try checkVulkanError(
            "Failed to submit Vulkan queue",
            self.dispatch.QueueSubmit(
                queue,
                submit_count,
                submits,
                fence,
            ),
        );
    }

    fn queuePresentKHR(
        self: *const Self,
        queue: c.VkQueue,
        present_info: *const c.VkPresentInfoKHR,
    ) !void {
        try checkVulkanError(
            "Failed to present Vulkan queue",
            self.dispatch.QueuePresentKHR(
                queue,
                present_info,
            ),
        );
    }

    fn createSwapchainKHR(
        self: *const Self,
        create_info: *const c.VkSwapchainCreateInfoKHR,
        swapchain: *c.VkSwapchainKHR,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan swapchain",
            self.dispatch.CreateSwapchainKHR(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                swapchain,
            ),
        );
    }

    fn destroySwapchainKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
    ) void {
        self.dispatch.DestroySwapchainKHR(
            self.device,
            swapchain,
            self.instance.allocation_callbacks,
        );
    }

    fn getSwapchainImagesKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
        count: *u32,
        images: [*c]c.VkImage,
    ) !void {
        const result = self.dispatch.GetSwapchainImagesKHR(
            self.device,
            swapchain,
            count,
            images,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            logWarn("Failed to get swapchain images: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to get swapchain images",
                result,
            );
        }
    }

    fn getSwapchainImagesKHRAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
        swapchain: c.VkSwapchainKHR,
    ) ![]c.VkImage {
        var count: u32 = undefined;
        try self.getSwapchainImagesKHR(
            swapchain,
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.VkImage,
            count,
        );
        errdefer allocator.free(result);

        try self.getSwapchainImagesKHR(
            swapchain,
            &count,
            result.ptr,
        );
        return result;
    }

    fn createImageView(
        self: *const Self,
        create_info: *const c.VkImageViewCreateInfo,
        image_view: *c.VkImageView,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan image view",
            self.dispatch.CreateImageView(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                image_view,
            ),
        );
    }

    fn destroyImageView(
        self: *const Self,
        image_view: c.VkImageView,
    ) void {
        self.dispatch.DestroyImageView(
            self.device,
            image_view,
            self.instance.allocation_callbacks,
        );
    }

    fn createShaderModule(
        self: *const Self,
        create_info: *const c.VkShaderModuleCreateInfo,
        shader_module: *c.VkShaderModule,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan shader module",
            self.dispatch.CreateShaderModule(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                shader_module,
            ),
        );
    }

    fn destroyShaderModule(
        self: *const Self,
        shader_module: c.VkShaderModule,
    ) void {
        self.dispatch.DestroyShaderModule(
            self.device,
            shader_module,
            self.instance.allocation_callbacks,
        );
    }

    fn createGraphicsPipelines(
        self: *const Self,
        pipeline_cache: c.VkPipelineCache,
        create_info_count: u32,
        create_infos: [*c]const c.VkGraphicsPipelineCreateInfo,
        pipelines: [*c]c.VkPipeline,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan graphics pipelines",
            self.dispatch.CreateGraphicsPipelines(
                self.device,
                pipeline_cache,
                create_info_count,
                create_infos,
                self.instance.allocation_callbacks,
                pipelines,
            ),
        );
    }

    fn destroyPipeline(
        self: *const Self,
        pipeline: c.VkPipeline,
    ) void {
        self.dispatch.DestroyPipeline(
            self.device,
            pipeline,
            self.instance.allocation_callbacks,
        );
    }

    fn createPipelineLayout(
        self: *const Self,
        create_info: *const c.VkPipelineLayoutCreateInfo,
        pipeline_layout: *c.VkPipelineLayout,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan pipeline layout",
            self.dispatch.CreatePipelineLayout(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                pipeline_layout,
            ),
        );
    }

    fn destroyPipelineLayout(
        self: *const Self,
        pipeline_layout: c.VkPipelineLayout,
    ) void {
        self.dispatch.DestroyPipelineLayout(
            self.device,
            pipeline_layout,
            self.instance.allocation_callbacks,
        );
    }

    fn createRenderPass(
        self: *const Self,
        create_info: *const c.VkRenderPassCreateInfo,
        render_pass: *c.VkRenderPass,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan render pass",
            self.dispatch.CreateRenderPass(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                render_pass,
            ),
        );
    }

    fn destroyRenderPass(
        self: *const Self,
        render_pass: c.VkRenderPass,
    ) void {
        self.dispatch.DestroyRenderPass(
            self.device,
            render_pass,
            self.instance.allocation_callbacks,
        );
    }

    fn createFrameBuffer(
        self: *const Self,
        create_info: *const c.VkFramebufferCreateInfo,
        frame_buffer: *c.VkFramebuffer,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan frame buffer",
            self.dispatch.CreateFramebuffer(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                frame_buffer,
            ),
        );
    }

    fn destroyFrameBuffer(
        self: *const Self,
        frame_buffer: c.VkFramebuffer,
    ) void {
        self.dispatch.DestroyFramebuffer(
            self.device,
            frame_buffer,
            self.instance.allocation_callbacks,
        );
    }

    fn createCommandPool(
        self: *const Self,
        create_info: *const c.VkCommandPoolCreateInfo,
        command_pool: *c.VkCommandPool,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan command pool",
            self.dispatch.CreateCommandPool(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                command_pool,
            ),
        );
    }

    fn destroyCommandPool(
        self: *const Self,
        command_pool: c.VkCommandPool,
    ) void {
        self.dispatch.DestroyCommandPool(
            self.device,
            command_pool,
            self.instance.allocation_callbacks,
        );
    }

    fn allocateCommandBuffers(
        self: *const Self,
        allocate_info: *const c.VkCommandBufferAllocateInfo,
        command_buffers: [*c]c.VkCommandBuffer,
    ) !void {
        try checkVulkanError(
            "Failed to allocate Vulkan command buffers",
            self.dispatch.AllocateCommandBuffers(
                self.device,
                allocate_info,
                command_buffers,
            ),
        );
    }

    fn createSemaphore(
        self: *const Self,
        create_info: *const c.VkSemaphoreCreateInfo,
        semaphore: *c.VkSemaphore,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan semaphore",
            self.dispatch.CreateSemaphore(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                semaphore,
            ),
        );
    }

    fn destroySemaphore(
        self: *const Self,
        semaphore: c.VkSemaphore,
    ) void {
        self.dispatch.DestroySemaphore(
            self.device,
            semaphore,
            self.instance.allocation_callbacks,
        );
    }

    fn createFence(
        self: *const Self,
        create_info: *const c.VkFenceCreateInfo,
        fence: *c.VkFence,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan fence",
            self.dispatch.CreateFence(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                fence,
            ),
        );
    }

    fn destroyFence(
        self: *const Self,
        fence: c.VkFence,
    ) void {
        self.dispatch.DestroyFence(
            self.device,
            fence,
            self.instance.allocation_callbacks,
        );
    }

    fn waitForFences(
        self: *const Self,
        fence_count: u32,
        fences: [*c]c.VkFence,
        wait_all: c.VkBool32,
        timeout: u64,
    ) !void {
        try checkVulkanError(
            "Failed to wait for Vulkan fences",
            self.dispatch.WaitForFences(
                self.device,
                fence_count,
                fences,
                wait_all,
                timeout,
            ),
        );
    }

    fn resetFences(
        self: *const Self,
        fence_count: u32,
        fences: [*c]c.VkFence,
    ) !void {
        try checkVulkanError(
            "Failed to reset Vulkan fences",
            self.dispatch.ResetFences(
                self.device,
                fence_count,
                fences,
            ),
        );
    }

    fn acquireNextImageKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
        timeout: u64,
        semaphore: c.VkSemaphore,
        fence: c.VkFence,
        image_index: *u32,
    ) !c.VkResult {
        const result = self.dispatch.AcquireNextImageKHR(
            self.device,
            swapchain,
            timeout,
            semaphore,
            fence,
            image_index,
        );

        // These are not errors
        if (result == c.VK_TIMEOUT or result == c.VK_NOT_READY or result == c.VK_SUBOPTIMAL_KHR) {
            return result;
        }

        try checkVulkanError(
            "Failed to acquire next Vulkan image",
            result,
        );

        return result;
    }

    fn waitIdle(self: *const Self) !void {
        try checkVulkanError(
            "Failed to wait for Vulkan device idle",
            self.dispatch.DeviceWaitIdle(self.device),
        );
    }
};

const SwapChainSupportDetails = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    fn init(
        allocator: std.mem.Allocator,
        instance: *VulkanInstance,
        physical_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) !Self {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            physical_device,
            surface,
            &capabilities,
        );

        const formats = try instance.getPhysicalDeviceSurfaceFormatsKHRAlloc(
            allocator,
            physical_device,
            surface,
        );
        errdefer allocator.free(formats);

        const present_modes = try instance.getPhysicalDeviceSurfacePresentModesKHRAlloc(
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

    fn deinit(self: *Self) void {
        self.allocator.free(self.formats);
        self.allocator.free(self.present_modes);
    }
};

const VulkanSurface = struct {
    const Self = @This();
    const Dispatch = struct {
        DestroySurfaceKHR: std.meta.Child(c.PFN_vkDestroySurfaceKHR) = undefined,
    };

    handle: c.VkSurfaceKHR,
    dispatch: Dispatch,
    instance: *const VulkanInstance,

    fn init(
        graphics_ctx: *const z3dfx.GraphicsContext,
        vulkan_library: *VulkanLibrary,
        instance: *const VulkanInstance,
    ) !Self {
        var surface: c.VkSurfaceKHR = undefined;
        try checkVulkanError(
            "Failed to create Vulkan surface",
            c.glfwCreateWindowSurface(
                instance.handle,
                graphics_ctx.options.window,
                instance.allocation_callbacks,
                &surface,
            ),
        );

        return .{
            .handle = surface,
            .dispatch = try vulkan_library.load(Dispatch, instance.handle),
            .instance = instance,
        };
    }

    fn deinit(self: *Self) void {
        self.dispatch.DestroySurfaceKHR(
            self.instance.handle,
            self.handle,
            self.instance.allocation_callbacks,
        );
    }
};

const VulkanSwapChain = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    handle: c.VkSwapchainKHR,
    device: *const VulkanDevice,
    images: []c.VkImage,
    image_views: []c.VkImageView,
    extent: c.VkExtent2D,
    format: c.VkFormat,
    frame_buffers: ?[]c.VkFramebuffer,

    fn init(
        graphics_ctx: *const z3dfx.GraphicsContext,
        instance: *VulkanInstance,
        device: *const VulkanDevice,
        surface: *const VulkanSurface,
    ) !Self {
        var swap_chain_support = try SwapChainSupportDetails.init(
            graphics_ctx.allocator,
            instance,
            device.physical_device,
            surface.handle,
        );
        defer swap_chain_support.deinit();

        const surface_format = chooseSwapSurfaceFormat(swap_chain_support.formats);
        const present_mode = chooseSwapPresentMode(swap_chain_support.present_modes);

        var window_width: c_int = undefined;
        var window_height: c_int = undefined;
        c.glfwGetFramebufferSize(
            graphics_ctx.options.window,
            &window_width,
            &window_height,
        );
        const extent = chooseSwapExtent(
            &swap_chain_support.capabilities,
            @intCast(window_width),
            @intCast(window_height),
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
                .surface = surface.handle,
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

        logDebug("---------------------------------------------------------------", .{});
        logDebug("Swap chain created", .{});
        logDebug("       Image count: {d}", .{image_count});
        logDebug("      Image format: {d}", .{surface_format.format});
        logDebug(" Image color space: {d}", .{surface_format.colorSpace});
        logDebug("      Image extent: {d}x{d}", .{ extent.width, extent.height });
        logDebug("      Present mode: {d}", .{present_mode});
        logDebug("---------------------------------------------------------------", .{});

        const swap_chain_images = try device.getSwapchainImagesKHRAlloc(
            graphics_ctx.allocator,
            swap_chain,
        );
        errdefer graphics_ctx.allocator.free(swap_chain_images);

        var swap_chain_image_views = try graphics_ctx.allocator.alloc(
            c.VkImageView,
            swap_chain_images.len,
        );
        errdefer graphics_ctx.allocator.free(swap_chain_image_views);

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

        return .{
            .allocator = graphics_ctx.allocator,
            .handle = swap_chain,
            .device = device,
            .images = swap_chain_images,
            .image_views = swap_chain_image_views,
            .extent = extent,
            .format = surface_format.format,
            .frame_buffers = null,
        };
    }

    fn deinit(self: *Self) void {
        if (self.frame_buffers) |frame_buffers| {
            for (frame_buffers) |frame_buffer| {
                self.device.destroyFrameBuffer(frame_buffer);
            }
            self.allocator.free(frame_buffers);
        }

        for (self.image_views) |image_view| {
            self.device.destroyImageView(image_view);
        }
        self.allocator.free(self.image_views);
        self.allocator.free(self.images);
        self.device.destroySwapchainKHR(self.handle);
    }

    fn chooseSwapSurfaceFormat(
        formats: []c.VkSurfaceFormatKHR,
    ) c.VkSurfaceFormatKHR {
        for (formats) |format| {
            if (format.format == c.VK_FORMAT_B8G8R8A8_SRGB and
                format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            {
                return format;
            }
        }
        return formats[0];
    }

    fn chooseSwapPresentMode(
        present_modes: []c.VkPresentModeKHR,
    ) c.VkPresentModeKHR {
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

    fn createFrameBuffers(
        self: *Self,
        render_pass: *const VulkanRenderPass,
    ) !void {
        self.frame_buffers = try self.allocator.alloc(
            c.VkFramebuffer,
            self.image_views.len,
        );

        for (self.image_views, 0..) |image_view, index| {
            const attachments = [1]c.VkImageView{image_view};

            const frame_buffer_create_info = std.mem.zeroInit(
                c.VkFramebufferCreateInfo,
                .{
                    .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
                    .renderPass = render_pass.handle,
                    .attachmentCount = 1,
                    .pAttachments = &attachments,
                    .width = self.extent.width,
                    .height = self.extent.height,
                    .layers = 1,
                },
            );

            try self.device.createFrameBuffer(
                &frame_buffer_create_info,
                &self.frame_buffers.?[index],
            );
        }
    }
};

const VulkanRenderPass = struct {
    const Self = @This();

    handle: c.VkRenderPass,
    device: *const VulkanDevice,

    fn init(device: *const VulkanDevice, format: c.VkFormat) !Self {
        const color_attachment = std.mem.zeroInit(
            c.VkAttachmentDescription,
            .{
                .format = format,
                .samples = c.VK_SAMPLE_COUNT_1_BIT,
                .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
                .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
                .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
                .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
                .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
                .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            },
        );

        const color_attachment_ref = std.mem.zeroInit(
            c.VkAttachmentReference,
            .{
                .attachment = 0,
                .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            },
        );

        const subpass = std.mem.zeroInit(
            c.VkSubpassDescription,
            .{
                .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
                .colorAttachmentCount = 1,
                .pColorAttachments = &color_attachment_ref,
            },
        );

        const dependency = std.mem.zeroInit(
            c.VkSubpassDependency,
            .{
                .srcSubpass = c.VK_SUBPASS_EXTERNAL,
                .dstSubpass = 0,
                .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .srcAccessMask = 0,
                .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            },
        );

        const render_pass_info = std.mem.zeroInit(
            c.VkRenderPassCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
                .attachmentCount = 1,
                .pAttachments = &color_attachment,
                .subpassCount = 1,
                .pSubpasses = &subpass,
                .dependencyCount = 1,
                .pDependencies = &dependency,
            },
        );

        var render_pass: c.VkRenderPass = undefined;
        try device.createRenderPass(
            &render_pass_info,
            &render_pass,
        );
        return .{
            .handle = render_pass,
            .device = device,
        };
    }

    fn deinit(self: *Self) void {
        self.device.destroyRenderPass(self.handle);
    }
};

const VulkanCommandQueue = struct {
    const Self = @This();
    const Dispatch = struct {
        BeginCommandBuffer: std.meta.Child(c.PFN_vkBeginCommandBuffer) = undefined,
        EndCommandBuffer: std.meta.Child(c.PFN_vkEndCommandBuffer) = undefined,
        ResetCommandBuffer: std.meta.Child(c.PFN_vkResetCommandBuffer) = undefined,
        CmdBeginRenderPass: std.meta.Child(c.PFN_vkCmdBeginRenderPass) = undefined,
        CmdEndRenderPass: std.meta.Child(c.PFN_vkCmdEndRenderPass) = undefined,
        CmdSetViewport: std.meta.Child(c.PFN_vkCmdSetViewport) = undefined,
        CmdSetScissor: std.meta.Child(c.PFN_vkCmdSetScissor) = undefined,
        CmdBindPipeline: std.meta.Child(c.PFN_vkCmdBindPipeline) = undefined,
        CmdDraw: std.meta.Child(c.PFN_vkCmdDraw) = undefined,
    };

    command_pool: c.VkCommandPool,
    command_buffers: [MaxFramesInFlight]c.VkCommandBuffer,
    device: *const VulkanDevice,
    dispatch: Dispatch,

    fn init(
        vulkan_library: *VulkanLibrary,
        device: *const VulkanDevice,
    ) !Self {
        const create_info = std.mem.zeroInit(
            c.VkCommandPoolCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                .queueFamilyIndex = device.queue_family_indices.graphics_family.?,
                .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            },
        );

        var command_pool: c.VkCommandPool = undefined;
        try device.createCommandPool(
            &create_info,
            &command_pool,
        );
        errdefer device.destroyCommandPool(command_pool);

        var command_buffers: [MaxFramesInFlight]c.VkCommandBuffer = undefined;
        const allocate_info = std.mem.zeroInit(
            c.VkCommandBufferAllocateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
                .commandPool = command_pool,
                .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
                .commandBufferCount = command_buffers.len,
            },
        );

        try device.allocateCommandBuffers(
            &allocate_info,
            &command_buffers,
        );

        return .{
            .command_pool = command_pool,
            .device = device,
            .command_buffers = command_buffers,
            .dispatch = try vulkan_library.load(Dispatch, device.instance.handle),
        };
    }

    fn deinit(self: *Self) void {
        self.device.destroyCommandPool(self.command_pool);
    }

    fn begin(self: *Self, frame_index: u32) !void {
        const begin_info = std.mem.zeroInit(
            c.VkCommandBufferBeginInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                //.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
            },
        );

        try checkVulkanError(
            "Failed to begin command buffer",
            self.dispatch.BeginCommandBuffer(self.command_buffers[frame_index], &begin_info),
        );
    }

    fn end(self: *Self, frame_index: u32) !void {
        try checkVulkanError(
            "Failed to end command buffer",
            self.dispatch.EndCommandBuffer(self.command_buffers[frame_index]),
        );
    }

    fn reset(self: *Self, frame_index: u32) !void {
        try checkVulkanError(
            "Failed to reset command buffer",
            self.dispatch.ResetCommandBuffer(self.command_buffers[frame_index], 0),
        );
    }

    fn beginRenderPass(
        self: *Self,
        render_pass: c.VkRenderPass,
        framebuffer: c.VkFramebuffer,
        extent: c.VkExtent2D,
        frame_index: u32,
    ) void {
        const begin_info = std.mem.zeroInit(
            c.VkRenderPassBeginInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                .renderPass = render_pass,
                .framebuffer = framebuffer,
                .renderArea = .{
                    .offset = .{ .x = 0, .y = 0 },
                    .extent = extent,
                },
                .clearValueCount = 1,
                .pClearValues = &[_]c.VkClearValue{
                    .{
                        .color = .{
                            .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
                        },
                    },
                },
            },
        );

        self.dispatch.CmdBeginRenderPass(
            self.command_buffers[frame_index],
            &begin_info,
            c.VK_SUBPASS_CONTENTS_INLINE,
        );
    }

    fn endRenderPass(self: *Self, frame_index: u32) void {
        self.dispatch.CmdEndRenderPass(self.command_buffers[frame_index]);
    }

    fn setViewport(self: *Self, viewport: c.VkViewport, frame_index: u32) void {
        self.dispatch.CmdSetViewport(self.command_buffers[frame_index], 0, 1, &viewport);
    }

    fn setScissor(self: *Self, scissor: c.VkRect2D, frame_index: u32) void {
        self.dispatch.CmdSetScissor(self.command_buffers[frame_index], 0, 1, &scissor);
    }

    fn bindPipeline(self: *Self, pipeline: c.VkPipeline, frame_index: u32) void {
        self.dispatch.CmdBindPipeline(
            self.command_buffers[frame_index],
            c.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipeline,
        );
    }

    fn draw(
        self: *Self,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
        frame_index: u32,
    ) void {
        self.dispatch.CmdDraw(
            self.command_buffers[frame_index],
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
        );
    }
};

const VulkanProgram = struct {
    const Self = @This();

    device: *const VulkanDevice,
    pipeline_layout: c.VkPipelineLayout,
    vertex_shader: c.VkShaderModule,
    fragment_shader: c.VkShaderModule,

    fn init(
        device: *const VulkanDevice,
        vertex_shader: c.VkShaderModule,
        fragment_shader: c.VkShaderModule,
    ) !Self {
        const pipeline_layout_create_info = std.mem.zeroInit(
            c.VkPipelineLayoutCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
                .setLayoutCount = 0,
                .pSetLayouts = null,
                .pushConstantRangeCount = 0,
                .pPushConstantRanges = null,
            },
        );

        var pipeline_layout: c.VkPipelineLayout = undefined;
        try device.createPipelineLayout(
            &pipeline_layout_create_info,
            &pipeline_layout,
        );
        return .{
            .device = device,
            .pipeline_layout = pipeline_layout,
            .vertex_shader = vertex_shader,
            .fragment_shader = fragment_shader,
        };
    }

    fn deinit(self: *Self) void {
        self.device.destroyPipelineLayout(self.pipeline_layout);
    }
};

const VulkanPipeline = struct {
    const Self = @This();

    device: *const VulkanDevice,
    handle: c.VkPipeline,

    fn init(
        device: *const VulkanDevice,
        program: *const VulkanProgram,
        render_pass: *const VulkanRenderPass,
    ) !Self {
        const vertex_input_info = std.mem.zeroInit(
            c.VkPipelineVertexInputStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
                .vertexBindingDescriptionCount = 0,
                .pVertexBindingDescriptions = null,
                .vertexAttributeDescriptionCount = 0,
                .pVertexAttributeDescriptions = null,
            },
        );

        const input_assembly = std.mem.zeroInit(
            c.VkPipelineInputAssemblyStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
                .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
                .primitiveRestartEnable = c.VK_FALSE,
            },
        );

        const viewport_state = std.mem.zeroInit(
            c.VkPipelineViewportStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
                .viewportCount = 1,
                //.pViewports = &viewport,
                .scissorCount = 1,
                //.pScissors = &scissor,
            },
        );

        const rasterizer = std.mem.zeroInit(
            c.VkPipelineRasterizationStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
                .depthClampEnable = c.VK_FALSE,
                .rasterizerDiscardEnable = c.VK_FALSE,
                .polygonMode = c.VK_POLYGON_MODE_FILL,
                .lineWidth = 1.0,
                .cullMode = c.VK_CULL_MODE_BACK_BIT,
                .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
                .depthBiasEnable = c.VK_FALSE,
            },
        );

        const multisampling = std.mem.zeroInit(
            c.VkPipelineMultisampleStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
                .sampleShadingEnable = c.VK_FALSE,
                .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
            },
        );

        const color_blend_attachment = std.mem.zeroInit(
            c.VkPipelineColorBlendAttachmentState,
            .{
                .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
                .blendEnable = c.VK_FALSE,
            },
        );

        const color_blending = std.mem.zeroInit(
            c.VkPipelineColorBlendStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
                .logicOpEnable = c.VK_FALSE,
                .logicOp = c.VK_LOGIC_OP_COPY,
                .attachmentCount = 1,
                .pAttachments = &color_blend_attachment,
            },
        );

        const dynamic_states = [_]c.VkDynamicState{
            c.VK_DYNAMIC_STATE_VIEWPORT,
            c.VK_DYNAMIC_STATE_SCISSOR,
        };

        const dynamic_state = std.mem.zeroInit(
            c.VkPipelineDynamicStateCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
                .dynamicStateCount = @as(u32, dynamic_states.len),
                .pDynamicStates = &dynamic_states,
            },
        );

        const stages = [_]c.VkPipelineShaderStageCreateInfo{
            c.VkPipelineShaderStageCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
                .module = program.vertex_shader,
                .pName = "main",
            },
            c.VkPipelineShaderStageCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
                .module = program.fragment_shader,
                .pName = "main",
            },
        };

        const pipeline_create_info = std.mem.zeroInit(
            c.VkGraphicsPipelineCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
                .stageCount = 2,
                .pStages = &stages,
                .pVertexInputState = &vertex_input_info,
                .pInputAssemblyState = &input_assembly,
                .pViewportState = &viewport_state,
                .pRasterizationState = &rasterizer,
                .pMultisampleState = &multisampling,
                .pColorBlendState = &color_blending,
                .pDynamicState = &dynamic_state,
                .layout = program.pipeline_layout,
                .renderPass = render_pass.handle,
                .subpass = 0,
                //.basePipelineHandle = c.VK_NULL_HANDLE,
            },
        );

        var pipeline: c.VkPipeline = undefined;
        try device.createGraphicsPipelines(
            null,
            1,
            &pipeline_create_info,
            &pipeline,
        );

        return .{
            .device = device,
            .handle = pipeline,
        };
    }

    fn deinit(self: *Self) void {
        self.device.destroyPipeline(self.handle);
    }
};

const PipelineKey = struct {
    program: z3dfx.ProgramHandle,
};

const VulkanContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    vulkan_library: VulkanLibrary,
    instance: *VulkanInstance,
    device: *VulkanDevice,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    surface: *VulkanSurface,
    swap_chain: *VulkanSwapChain,
    main_render_pass: *VulkanRenderPass,
    command_queue: *VulkanCommandQueue,
    debug_messenger: ?c.VkDebugUtilsMessengerEXT,

    shader_modules: [z3dfx.MaxShaderHandles]c.VkShaderModule,
    programs: [z3dfx.MaxProgramHandles]VulkanProgram,
    pipelines: std.AutoHashMap(PipelineKey, VulkanPipeline),

    image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore,
    render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore,
    in_flight_fences: [MaxFramesInFlight]c.VkFence,

    current_image_index: u32,
    current_frame: u32,

    fn init(graphics_ctx: *const z3dfx.GraphicsContext) !Self {
        var vulkan_library = try VulkanLibrary.init();
        errdefer vulkan_library.deinit();

        var instance = try graphics_ctx.allocator.create(VulkanInstance);
        errdefer graphics_ctx.allocator.destroy(instance);

        instance.* = try VulkanInstance.init(
            graphics_ctx,
            &vulkan_library,
            null,
        );
        errdefer instance.deinit();

        const debug_messenger = try setupDebugMessenger(
            &graphics_ctx.options,
            instance,
        );

        var surface = try graphics_ctx.allocator.create(VulkanSurface);
        errdefer graphics_ctx.allocator.destroy(surface);

        surface.* = try VulkanSurface.init(
            graphics_ctx,
            &vulkan_library,
            instance,
        );
        errdefer surface.deinit();

        var device = try graphics_ctx.allocator.create(VulkanDevice);
        errdefer graphics_ctx.allocator.destroy(device);

        device.* = try VulkanDevice.init(
            graphics_ctx,
            &vulkan_library,
            instance,
            surface,
        );
        errdefer device.deinit();

        var graphics_queue: c.VkQueue = undefined;
        device.getDeviceQueue(
            device.queue_family_indices.graphics_family.?,
            0,
            &graphics_queue,
        );

        var present_queue: c.VkQueue = undefined;
        device.getDeviceQueue(
            device.queue_family_indices.present_family.?,
            0,
            &present_queue,
        );

        var swap_chain = try graphics_ctx.allocator.create(VulkanSwapChain);
        errdefer graphics_ctx.allocator.destroy(swap_chain);

        swap_chain.* = try VulkanSwapChain.init(
            graphics_ctx,
            instance,
            device,
            surface,
        );
        errdefer swap_chain.deinit();

        var main_render_pass = try graphics_ctx.allocator.create(VulkanRenderPass);
        errdefer graphics_ctx.allocator.destroy(main_render_pass);

        main_render_pass.* = try VulkanRenderPass.init(
            device,
            swap_chain.format,
        );
        errdefer main_render_pass.deinit();

        try swap_chain.createFrameBuffers(main_render_pass);

        var command_queue = try graphics_ctx.allocator.create(VulkanCommandQueue);
        errdefer graphics_ctx.allocator.destroy(command_queue);

        command_queue.* = try VulkanCommandQueue.init(&vulkan_library, device);
        errdefer command_queue.deinit();

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

        var image_available_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
        var render_finished_semaphores: [MaxFramesInFlight]c.VkSemaphore = undefined;
        var in_flight_fences: [MaxFramesInFlight]c.VkFence = undefined;

        for (0..MaxFramesInFlight) |i| {
            try device.createSemaphore(
                &semaphore_create_info,
                &image_available_semaphores[i],
            );

            try device.createSemaphore(
                &semaphore_create_info,
                &render_finished_semaphores[i],
            );

            try device.createFence(
                &fence_create_info,
                &in_flight_fences[i],
            );
        }

        return .{
            .allocator = graphics_ctx.allocator,
            .vulkan_library = vulkan_library,
            .instance = instance,
            .debug_messenger = debug_messenger,
            .device = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
            .surface = surface,
            .swap_chain = swap_chain,
            .main_render_pass = main_render_pass,
            .command_queue = command_queue,
            .shader_modules = undefined,
            .programs = undefined,
            .pipelines = .init(graphics_ctx.allocator),
            .image_available_semaphores = image_available_semaphores,
            .render_finished_semaphores = render_finished_semaphores,
            .in_flight_fences = in_flight_fences,
            .current_image_index = 0,
            .current_frame = 0,
        };
    }

    fn deinit(self: *Self) void {
        self.device.waitIdle() catch {
            logErr("Failed to wait for Vulkan device to become idle", .{});
        };

        for (0..MaxFramesInFlight) |i| {
            self.device.destroySemaphore(self.image_available_semaphores[i]);
            self.device.destroySemaphore(self.render_finished_semaphores[i]);
            self.device.destroyFence(self.in_flight_fences[i]);
        }

        var iterator = self.pipelines.valueIterator();
        while (iterator.next()) |pipeline| {
            pipeline.deinit();
        }
        self.pipelines.deinit();

        self.command_queue.deinit();
        self.allocator.destroy(self.command_queue);

        self.main_render_pass.deinit();
        self.allocator.destroy(self.main_render_pass);

        self.swap_chain.deinit();
        self.allocator.destroy(self.swap_chain);

        self.surface.deinit();
        self.allocator.destroy(self.surface);

        self.device.deinit();
        self.allocator.destroy(self.device);

        if (self.debug_messenger) |debug_messenger| {
            self.instance.destroyDebugUtilsMessengerEXT(debug_messenger);
        }
        self.instance.deinit();
        self.allocator.destroy(self.instance);

        self.vulkan_library.deinit();
    }

    fn setupDebugMessenger(options: *const z3dfx.GraphicsOptions, instance: *VulkanInstance) !?c.VkDebugUtilsMessengerEXT {
        if (!options.enable_vulkan_debug) {
            return null;
        }

        const create_info = std.mem.zeroInit(
            c.VkDebugUtilsMessengerCreateInfoEXT,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                .pfnUserCallback = @as(c.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&debugCallback)),
            },
        );

        var debug_messenger: c.VkDebugUtilsMessengerEXT = undefined;
        try instance.createDebugUtilsMessengerEXT(
            &create_info,
            &debug_messenger,
        );
        return debug_messenger;
    }
};

var context: VulkanContext = undefined;

pub const VulkanRenderer = struct {
    pub fn init(graphics_ctx: *const z3dfx.GraphicsContext) !VulkanRenderer {
        logDebug("Initializing Vulkan renderer...", .{});

        context = try .init(graphics_ctx);

        return .{};
    }

    pub fn deinit(_: *const VulkanRenderer) void {
        logDebug("Deinitializing Vulkan renderer...", .{});

        context.deinit();
    }

    pub fn getSwapchainSize(_: *const VulkanRenderer) z3dfx.Size {
        return .{
            .width = @as(f32, @floatFromInt(context.swap_chain.extent.width)),
            .height = @as(f32, @floatFromInt(context.swap_chain.extent.height)),
        };
    }

    pub fn createShader(
        _: *const VulkanRenderer,
        handle: z3dfx.ShaderHandle,
        data: []align(@alignOf(u32)) const u8,
    ) !void {
        const create_info = std.mem.zeroInit(
            c.VkShaderModuleCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
                .codeSize = @as(u64, data.len),
                .pCode = std.mem.bytesAsSlice(u32, data).ptr,
            },
        );

        try context.device.createShaderModule(
            &create_info,
            &context.shader_modules[handle],
        );
        logDebug("Created Vulkan shader module: {d}", .{handle});
    }

    pub fn destroyShader(
        _: *VulkanRenderer,
        handle: z3dfx.ShaderHandle,
    ) void {
        context.device.destroyShaderModule(context.shader_modules[handle]);
        logDebug("Destroyed Vulkan shader module: {d}", .{handle});
    }

    pub fn createProgram(
        _: *const VulkanRenderer,
        handle: z3dfx.ProgramHandle,
        vertex_shader: z3dfx.ShaderHandle,
        fragment_shader: z3dfx.ShaderHandle,
    ) !void {
        context.programs[handle] = try VulkanProgram.init(
            context.device,
            context.shader_modules[vertex_shader],
            context.shader_modules[fragment_shader],
        );

        logDebug("Created Vulkan program: {d}", .{handle});
    }

    pub fn destroyProgram(
        _: *const VulkanRenderer,
        handle: z3dfx.ProgramHandle,
    ) void {
        context.programs[handle].deinit();
        logDebug("Destroyed Vulkan program: {d}", .{handle});
    }

    pub fn beginFrame(_: *const VulkanRenderer) !void {
        try context.device.waitForFences(
            1,
            &context.in_flight_fences[context.current_frame],
            c.VK_TRUE,
            c.UINT64_MAX,
        );
        try context.device.resetFences(1, &context.in_flight_fences[context.current_frame]);

        _ = try context.device.acquireNextImageKHR(
            context.swap_chain.handle,
            c.UINT64_MAX,
            context.image_available_semaphores[context.current_frame],
            null,
            &context.current_image_index,
        );

        try context.command_queue.reset(context.current_frame);
        try context.command_queue.begin(context.current_frame);

        context.command_queue.beginRenderPass(
            context.main_render_pass.handle,
            context.swap_chain.frame_buffers.?[context.current_image_index],
            context.swap_chain.extent,
            context.current_frame,
        );
    }

    pub fn endFrame(_: *const VulkanRenderer) !void {
        context.command_queue.endRenderPass(context.current_frame);
        try context.command_queue.end(context.current_frame);

        const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const wait_semaphores = [_]c.VkSemaphore{context.image_available_semaphores[context.current_frame]};
        const signal_semaphores = [_]c.VkSemaphore{context.render_finished_semaphores[context.current_frame]};
        const submit_info = std.mem.zeroInit(
            c.VkSubmitInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &wait_semaphores,
                .pWaitDstStageMask = &wait_stages,
                .commandBufferCount = 1,
                .pCommandBuffers = &context.command_queue.command_buffers[context.current_frame],
                .signalSemaphoreCount = 1,
                .pSignalSemaphores = &signal_semaphores,
            },
        );

        try context.device.queueSubmit(
            context.graphics_queue,
            1,
            &submit_info,
            context.in_flight_fences[context.current_frame],
        );

        const present_info = std.mem.zeroInit(
            c.VkPresentInfoKHR,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &signal_semaphores,
                .swapchainCount = 1,
                .pSwapchains = &context.swap_chain.handle,
                .pImageIndices = &context.current_image_index,
            },
        );

        try context.device.queuePresentKHR(context.present_queue, &present_info);

        context.current_frame = (context.current_frame + 1) % MaxFramesInFlight;
    }

    pub fn setViewport(_: *const VulkanRenderer, viewport: z3dfx.Rect) void {
        const vk_viewport = std.mem.zeroInit(
            c.VkViewport,
            .{
                .x = @as(f32, viewport.position.x),
                .y = @as(f32, viewport.position.y),
                .width = @as(f32, viewport.size.width),
                .height = @as(f32, viewport.size.height),
                .minDepth = 0,
                .maxDepth = 1,
            },
        );
        context.command_queue.setViewport(vk_viewport, context.current_frame);
    }

    pub fn setScissor(_: *const VulkanRenderer, scissor: z3dfx.Rect) void {
        const vk_scissor = std.mem.zeroInit(
            c.VkRect2D,
            .{
                .offset = c.VkOffset2D{
                    .x = @as(i32, @intFromFloat(scissor.position.x)),
                    .y = @as(i32, @intFromFloat(scissor.position.y)),
                },
                .extent = c.VkExtent2D{
                    .width = @as(u32, @intFromFloat(scissor.size.width)),
                    .height = @as(u32, @intFromFloat(scissor.size.height)),
                },
            },
        );
        context.command_queue.setScissor(vk_scissor, context.current_frame);
    }

    pub fn bindProgram(self: *const VulkanRenderer, program: z3dfx.ProgramHandle) void {
        const pipeline = self.getPipeline(program) catch {
            logErr("Failed to bind Vulkan program: {d}", .{program});
            return;
        };
        context.command_queue.bindPipeline(pipeline.handle, context.current_frame);
    }
    pub fn draw(
        _: *const VulkanRenderer,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        context.command_queue.draw(
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
            context.current_frame,
        );
    }

    fn getPipeline(
        _: *const VulkanRenderer,
        program: z3dfx.ProgramHandle,
    ) !VulkanPipeline {
        const key = PipelineKey{ .program = program };
        var pipeline = context.pipelines.get(key);
        if (pipeline != null) {
            return pipeline.?;
        }

        pipeline = try VulkanPipeline.init(
            context.device,
            &context.programs[program],
            context.main_render_pass,
        );
        try context.pipelines.put(key, pipeline.?);
        return pipeline.?;
    }
};
