const std = @import("std");
const builtin = @import("builtin");

const c = @import("../c.zig");
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
    message_severity: c.vk.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.vk.VkDebugUtilsMessageTypeFlagsEXT,
    p_callback_data: [*c]const c.vk.VkDebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.c) c.vk.VkBool32 {
    _ = p_user_data;

    const allowed_flags = c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    if (message_type & allowed_flags == 0) {
        return c.vk.VK_FALSE;
    }

    if (message_severity & c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT == c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
        logErr("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT == c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        logWarn("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT == c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
        logInfo("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT == c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) {
        logDebug("{s}", .{p_callback_data.*.pMessage});
    }

    return c.vk.VK_FALSE;
}

fn getPhysicalDeviceTypeLabel(device_type: c.vk.VkPhysicalDeviceType) []const u8 {
    return switch (device_type) {
        c.vk.VK_PHYSICAL_DEVICE_TYPE_OTHER => "Other",
        c.vk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => "Integrated GPU",
        c.vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => "Discrete GPU",
        c.vk.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => "Virtual GPU",
        c.vk.VK_PHYSICAL_DEVICE_TYPE_CPU => "CPU",
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

fn checkVulkanError(comptime message: []const u8, result: c.vk.VkResult) !void {
    return switch (result) {
        c.vk.VK_SUCCESS => {},
        c.vk.VK_ERROR_OUT_OF_HOST_MEMORY => {
            logErr("{s}: out of host memory", .{message});
            return error.VulkanOutOfHostMemory;
        },
        c.vk.VK_ERROR_OUT_OF_DEVICE_MEMORY => {
            logErr("{s}: out of device memory", .{message});
            return error.VulkanOutOfDeviceMemory;
        },
        c.vk.VK_ERROR_INITIALIZATION_FAILED => {
            logErr("{s}: initialization failed", .{message});
            return error.VulkanInitializationFailed;
        },
        c.vk.VK_ERROR_LAYER_NOT_PRESENT => {
            logErr("{s}: layer not present", .{message});
            return error.VulkanLayerNotPresent;
        },
        c.vk.VK_ERROR_EXTENSION_NOT_PRESENT => {
            logErr("{s}: extension not present", .{message});
            return error.VulkanExtensionNotPresent;
        },
        c.vk.VK_ERROR_FEATURE_NOT_PRESENT => {
            logErr("{s}: feature not present", .{message});
            return error.VulkanFeatureNotPresent;
        },
        c.vk.VK_ERROR_INCOMPATIBLE_DRIVER => {
            logErr("{s}: incompatible driver", .{message});
            return error.VulkanIncompatibleDriver;
        },
        c.vk.VK_ERROR_TOO_MANY_OBJECTS => {
            logErr("{s}: too many objects", .{message});
            return error.VulkanTooManyObjects;
        },
        c.vk.VK_ERROR_DEVICE_LOST => {
            logErr("{s}: device lost", .{message});
            return error.VulkanDeviceLost;
        },
        else => {
            logErr("{s}: {d}", .{ message, result });
            return error.VulkanUnknownError;
        },
    };
}

const VulkanLibrary = struct {
    const Self = @This();
    const LibraryNames = switch (builtin.os.tag) {
        .windows => &[_][]const u8{"vulkan-1.dll"},
        .ios, .macos, .tvos, .watchos => &[_][]const u8{ "libvulkan.dylib", "libvulkan.1.dylib", "libMoltenVK.dylib" },
        else => &[_][]const u8{ "libvulkan.so.1", "libvulkan.so" },
    };
    const Dispatch = struct {
        CreateInstance: std.meta.Child(c.vk.PFN_vkCreateInstance) = undefined,
        EnumerateInstanceExtensionProperties: std.meta.Child(c.vk.PFN_vkEnumerateInstanceExtensionProperties) = undefined,
        EnumerateInstanceLayerProperties: std.meta.Child(c.vk.PFN_vkEnumerateInstanceLayerProperties) = undefined,
    };

    handle: std.DynLib,
    get_instance_proc_addr: std.meta.Child(c.vk.PFN_vkGetInstanceProcAddr),
    dispatch: Dispatch,

    fn init() !Self {
        var library = try loadLibrary();
        const get_instance_proc_addr = library.lookup(
            std.meta.Child(c.vk.PFN_vkGetInstanceProcAddr),
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
        self.dispatch = try self.load(Dispatch, "", null);
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
        instance: c.vk.VkInstance,
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
        comptime suffix: []const u8,
        instance: c.vk.VkInstance,
    ) !TDispatch {
        var dispatch = TDispatch{};
        inline for (@typeInfo(TDispatch).@"struct".fields) |field| {
            @field(dispatch, field.name) = try self.get_proc(
                ?field.type,
                instance,
                "vk" ++ field.name ++ suffix,
            );
        }
        return dispatch;
    }

    fn createInstance(
        self: *Self,
        create_info: *const c.vk.VkInstanceCreateInfo,
        allocation_callbacks: ?*const c.vk.VkAllocationCallbacks,
        instance: *c.vk.VkInstance,
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
        properties: [*c]c.vk.VkExtensionProperties,
    ) !void {
        const result = self.dispatch.EnumerateInstanceExtensionProperties(
            layer_name,
            count,
            properties,
        );
        if (result == c.vk.VK_INCOMPLETE) {
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
    ) ![]c.vk.VkExtensionProperties {
        var count: u32 = undefined;
        try self.enumerateInstanceExtensionProperties(
            layer_name,
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.vk.VkExtensionProperties,
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
        properties: [*c]c.vk.VkLayerProperties,
    ) !void {
        const result = self.dispatch.EnumerateInstanceLayerProperties(
            count,
            properties,
        );
        if (result == c.vk.VK_INCOMPLETE) {
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
    ) ![]c.vk.VkLayerProperties {
        var count: u32 = undefined;
        try self.enumerateInstanceLayerProperties(
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.vk.VkLayerProperties,
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
        DestroyInstance: std.meta.Child(c.vk.PFN_vkDestroyInstance) = undefined,
        EnumeratePhysicalDevices: std.meta.Child(c.vk.PFN_vkEnumeratePhysicalDevices) = undefined,
        GetPhysicalDeviceProperties: std.meta.Child(c.vk.PFN_vkGetPhysicalDeviceProperties) = undefined,
        GetPhysicalDeviceFeatures: std.meta.Child(c.vk.PFN_vkGetPhysicalDeviceFeatures) = undefined,
        GetPhysicalDeviceMemoryProperties: std.meta.Child(c.vk.PFN_vkGetPhysicalDeviceMemoryProperties) = undefined,
        GetPhysicalDeviceQueueFamilyProperties: std.meta.Child(c.vk.PFN_vkGetPhysicalDeviceQueueFamilyProperties) = undefined,
        CreateDebugUtilsMessengerEXT: std.meta.Child(c.vk.PFN_vkCreateDebugUtilsMessengerEXT) = undefined,
        DestroyDebugUtilsMessengerEXT: std.meta.Child(c.vk.PFN_vkDestroyDebugUtilsMessengerEXT) = undefined,
        CreateDevice: std.meta.Child(c.vk.PFN_vkCreateDevice) = undefined,
    };

    handle: c.vk.VkInstance,
    allocation_callbacks: ?*c.vk.VkAllocationCallbacks,
    dispatch: Dispatch,

    fn init(
        graphics_ctx: *const z3dfx.GraphicsContext,
        vulkan_library: *VulkanLibrary,
        allocation_callbacks: ?*c.vk.VkAllocationCallbacks,
    ) !Self {
        var extensions = std.ArrayList([*:0]const u8).init(
            graphics_ctx.allocator,
        );
        defer extensions.deinit();

        var glfw_extension_count: u32 = 0;
        const glfw_extensions = c.glfw.glfwGetRequiredInstanceExtensions(
            &glfw_extension_count,
        );
        for (0..glfw_extension_count) |index| {
            try extensions.append(glfw_extensions[index]);
        }

        switch (builtin.target.os.tag) {
            .macos, .ios, .tvos => {
                try extensions.append(c.vk.VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
            },
            else => {},
        }

        if (graphics_ctx.options.enable_vulkan_debug) {
            try extensions.append(c.vk.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
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
            c.vk.VkApplicationInfo,
            .{
                .sType = c.vk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
                .pApplicationName = "z3dfx",
                .applicationVersion = c.vk.VK_MAKE_VERSION(1, 0, 0),
                .pEngineName = "z3dfx",
                .engineVersion = c.vk.VK_MAKE_VERSION(1, 0, 0),
                .apiVersion = c.vk.VK_API_VERSION_1_0,
            },
        );

        var create_info = std.mem.zeroInit(
            c.vk.VkInstanceCreateInfo,
            .{
                .sType = c.vk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
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
                c.vk.VkDebugUtilsMessengerCreateInfoEXT,
                .{
                    .sType = c.vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                    .messageSeverity = c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                    .messageType = c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                    .pfnUserCallback = @as(c.vk.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&debugCallback)),
                },
            );
            create_info.pNext = &debug_create_info;
        }

        var instance: c.vk.VkInstance = undefined;
        try vulkan_library.createInstance(
            &create_info,
            allocation_callbacks,
            &instance,
        );

        return .{
            .handle = instance,
            .allocation_callbacks = allocation_callbacks,
            .dispatch = try vulkan_library.load(Dispatch, "", instance),
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
        physical_devices: [*c]c.vk.VkPhysicalDevice,
    ) !void {
        const result = self.dispatch.EnumeratePhysicalDevices(
            self.handle,
            count,
            physical_devices,
        );
        if (result == c.vk.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            logWarn("Failed to enumerate Vulkan physical devices: incomplete", .{});
        } else {
            try checkVulkanError(
                "Failed to enumerate Vulkan physical devices",
                result,
            );
        }
    }

    fn enumeratePhysicalDevicesAlloc(self: *Self, allocator: std.mem.Allocator) ![]c.vk.VkPhysicalDevice {
        var count: u32 = undefined;
        try self.enumeratePhysicalDevices(
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.vk.VkPhysicalDevice,
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
        physical_device: c.vk.VkPhysicalDevice,
        properties: *c.vk.VkPhysicalDeviceProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceProperties(physical_device, properties);
    }

    fn getPhysicalDeviceFeatures(
        self: *Self,
        physical_device: c.vk.VkPhysicalDevice,
        features: *c.vk.VkPhysicalDeviceFeatures,
    ) void {
        self.dispatch.GetPhysicalDeviceFeatures(physical_device, features);
    }

    fn getPhysicalDeviceMemoryProperties(
        self: *Self,
        physical_device: c.vk.VkPhysicalDevice,
        memory_properties: *c.vk.VkPhysicalDeviceMemoryProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceMemoryProperties(physical_device, memory_properties);
    }

    fn getPhysicalDeviceQueueFamilyProperties(
        self: *Self,
        physical_device: c.vk.VkPhysicalDevice,
        count: *u32,
        queue_family_properties: [*c]c.vk.VkQueueFamilyProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceQueueFamilyProperties(physical_device, count, queue_family_properties);
    }

    fn getPhysicalDeviceQueueFamilyPropertiesAlloc(
        self: *Self,
        allocator: std.mem.Allocator,
        physical_device: c.vk.VkPhysicalDevice,
    ) ![]c.vk.VkQueueFamilyProperties {
        var count: u32 = undefined;
        self.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, null);

        const result = try allocator.alloc(
            c.vk.VkQueueFamilyProperties,
            count,
        );
        errdefer allocator.free(result);

        self.getPhysicalDeviceQueueFamilyProperties(physical_device, &count, result.ptr);
        return result;
    }

    fn createDebugUtilsMessengerEXT(
        self: *Self,
        create_info: *const c.vk.VkDebugUtilsMessengerCreateInfoEXT,
        allocation_callbacks: ?*const c.vk.VkAllocationCallbacks,
        messenger: *c.vk.VkDebugUtilsMessengerEXT,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan debug messenger",
            self.dispatch.CreateDebugUtilsMessengerEXT(self.handle, create_info, allocation_callbacks, messenger),
        );
    }

    fn destroyDebugUtilsMessengerEXT(
        self: *Self,
        messenger: c.vk.VkDebugUtilsMessengerEXT,
        allocation_callbacks: ?*const c.vk.VkAllocationCallbacks,
    ) void {
        self.dispatch.DestroyDebugUtilsMessengerEXT(self.handle, messenger, allocation_callbacks);
    }

    fn createDevice(
        self: *Self,
        physical_device: c.vk.VkPhysicalDevice,
        create_info: *const c.vk.VkDeviceCreateInfo,
        allocation_callbacks: ?*const c.vk.VkAllocationCallbacks,
        device: *c.vk.VkDevice,
    ) !void {
        try checkVulkanError(
            "Failed to create Vulkan device",
            self.dispatch.CreateDevice(physical_device, create_info, allocation_callbacks, device),
        );
    }
};

const VulkanDevice = struct {
    const Self = @This();
    const Dispatch = struct {
        DestroyDevice: std.meta.Child(c.vk.PFN_vkDestroyDevice) = undefined,
    };
    const QueueFamilyIndices = struct {
        graphics_family: ?u32 = null,

        fn isComplete(self: QueueFamilyIndices) bool {
            return self.graphics_family != null;
        }
    };

    physical_device: c.vk.VkPhysicalDevice,
    device: c.vk.VkDevice,
    dispatch: Dispatch,

    fn init(
        graphics_ctx: *const z3dfx.GraphicsContext,
        vulkan_library: VulkanLibrary,
        instance: *VulkanInstance,
    ) !Self {
        const physical_devices = try instance.enumeratePhysicalDevicesAlloc(
            graphics_ctx.allocator,
        );
        defer graphics_ctx.allocator.free(physical_devices);

        if (physical_devices.len == 0) {
            logErr("No Vulkan physical devices found", .{});
            return error.NoPhysicalDevicesFound;
        }

        var selected_physical_device: c.vk.VkPhysicalDevice = null;
        var selected_physical_device_score: u32 = 0;
        var selected_physical_device_index: usize = 0;
        var selected_physical_device_properties = std.mem.zeroes(c.vk.VkPhysicalDeviceProperties);
        for (physical_devices, 0..) |physical_device, index| {
            const score = try rateDeviceSuitability(
                graphics_ctx.allocator,
                instance,
                physical_device,
            );

            var properties = std.mem.zeroes(c.vk.VkPhysicalDeviceProperties);
            instance.getPhysicalDeviceProperties(physical_device, &properties);

            logDebug("  Physical device: {d}", .{index});
            logDebug("             Name: {s}", .{properties.deviceName});
            logDebug("      API version: {d}.{d}.{d}", .{
                c.vk.VK_API_VERSION_MAJOR(properties.apiVersion),
                c.vk.VK_API_VERSION_MINOR(properties.apiVersion),
                c.vk.VK_API_VERSION_PATCH(properties.apiVersion),
            });
            logDebug("      API variant: {d}", .{
                c.vk.VK_API_VERSION_VARIANT(properties.apiVersion),
            });
            logDebug("   Driver version: {x}", .{properties.driverVersion});
            logDebug("        Vendor ID: {x}", .{properties.vendorID});
            logDebug("        Device ID: {x}", .{properties.deviceID});
            logDebug("             Type: {s}", .{getPhysicalDeviceTypeLabel(properties.deviceType)});
            logDebug("            Score: {d}", .{score});

            var memory_properties = std.mem.zeroes(c.vk.VkPhysicalDeviceMemoryProperties);
            instance.getPhysicalDeviceMemoryProperties(physical_device, &memory_properties);

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

        logDebug(
            "Using physical device {d}: {s}",
            .{ selected_physical_device_index, selected_physical_device_properties.deviceName },
        );

        const queue_family_indices = try findQueueFamilies(
            graphics_ctx.allocator,
            instance,
            selected_physical_device,
        );
        const queue_priorities = [_]f32{1.0};
        const device_queue_create_info = std.mem.zeroInit(
            c.vk.VkDeviceQueueCreateInfo,
            .{
                .sType = c.vk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = queue_family_indices.graphics_family.?,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
        );
        const physical_device_features = std.mem.zeroInit(
            c.vk.VkPhysicalDeviceFeatures,
            .{},
        );

        const validation_layers = try prepareValidationLayers(
            graphics_ctx.allocator,
            &graphics_ctx.options,
        );
        defer validation_layers.deinit();

        const device_create_info = std.mem.zeroInit(
            c.vk.VkDeviceCreateInfo,
            .{
                .sType = c.vk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .queueCreateInfoCount = 1,
                .pQueueCreateInfos = &device_queue_create_info,
                .enabledLayerCount = @as(u32, @intCast(validation_layers.items.len)),
                .ppEnabledLayerNames = validation_layers.items.ptr,
                .enabledExtensionCount = 0,
                .ppEnabledExtensionNames = null,
                .pEnabledFeatures = &physical_device_features,
            },
        );

        var device: c.vk.VkDevice = undefined;
        try instance.createDevice(
            selected_physical_device,
            &device_create_info,
            null,
            &device,
        );

        return .{
            .physical_device = selected_physical_device,
            .device = device,
            .dispatch = try vulkan_library.load(Dispatch, "", instance.handle),
        };
    }

    fn deinit(self: *Self) void {
        _ = self;
    }

    fn rateDeviceSuitability(
        allocator: std.mem.Allocator,
        instance: *VulkanInstance,
        physical_device: c.vk.VkPhysicalDevice,
    ) !u32 {
        var properties = std.mem.zeroes(c.vk.VkPhysicalDeviceProperties);
        var features = std.mem.zeroes(c.vk.VkPhysicalDeviceFeatures);
        var queue_family_properties = std.ArrayList(c.vk.VkQueueFamilyProperties).init(allocator);
        defer queue_family_properties.deinit();

        var score: u32 = 0;

        // Device properties
        instance.getPhysicalDeviceProperties(physical_device, &properties);
        if (properties.deviceType == c.vk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            score += 1000;
        }
        score += properties.limits.maxImageDimension2D;

        // Queue families
        const queue_family_indices = try findQueueFamilies(allocator, instance, physical_device);

        // Device features
        instance.getPhysicalDeviceFeatures(physical_device, &features);
        if (features.geometryShader == 0 or !queue_family_indices.isComplete()) {
            return 0;
        }

        return score;
    }

    fn findQueueFamilies(
        allocator: std.mem.Allocator,
        instance: *VulkanInstance,
        physical_device: c.vk.VkPhysicalDevice,
    ) !QueueFamilyIndices {
        var queue_family_indices = QueueFamilyIndices{};

        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
            allocator,
            physical_device,
        );
        defer allocator.free(queue_families);

        for (queue_families, 0..) |queue_family, index| {
            if (queue_family.queueFlags & c.vk.VK_QUEUE_GRAPHICS_BIT != 0) {
                queue_family_indices.graphics_family = @intCast(index);
            }

            if (queue_family_indices.isComplete()) {
                break;
            }
        }

        return queue_family_indices;
    }
};

const VulkanContext = struct {
    const Self = @This();

    vulkan_library: VulkanLibrary,
    instance: VulkanInstance,
    debug_messenger: ?c.vk.VkDebugUtilsMessengerEXT,

    fn init(graphics_ctx: *const z3dfx.GraphicsContext) !Self {
        var vulkan_library = try VulkanLibrary.init();
        errdefer vulkan_library.deinit();

        var instance = try VulkanInstance.init(
            graphics_ctx,
            &vulkan_library,
            null,
        );
        errdefer instance.deinit();

        const debug_messenger = try setupDebugMessenger(
            &graphics_ctx.options,
            &instance,
        );

        const device = try VulkanDevice.init(
            graphics_ctx,
            vulkan_library,
            &instance,
        );
        errdefer device.deinit();

        return .{
            .vulkan_library = vulkan_library,
            .instance = instance,
            .debug_messenger = debug_messenger,
        };
    }

    fn deinit(self: *Self) void {
        if (self.debug_messenger) |debug_messenger| {
            self.instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);
        }
        self.instance.deinit();
        self.vulkan_library.deinit();
    }

    fn setupDebugMessenger(options: *const z3dfx.GraphicsOptions, instance: *VulkanInstance) !?c.vk.VkDebugUtilsMessengerEXT {
        if (!options.enable_vulkan_debug) {
            return null;
        }

        const create_info = std.mem.zeroInit(
            c.vk.VkDebugUtilsMessengerCreateInfoEXT,
            .{
                .sType = c.vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
                .messageSeverity = c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
                .messageType = c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | c.vk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
                .pfnUserCallback = @as(c.vk.PFN_vkDebugUtilsMessengerCallbackEXT, @ptrCast(&debugCallback)),
            },
        );

        var debug_messenger: c.vk.VkDebugUtilsMessengerEXT = undefined;
        try instance.createDebugUtilsMessengerEXT(
            &create_info,
            null,
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

    pub fn deinit(self: *const VulkanRenderer) void {
        _ = self;
        logDebug("Deinitializing Vulkan renderer...", .{});

        context.deinit();
    }
};
