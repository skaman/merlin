const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const vk = @import("vulkan.zig");

pub const Library = struct {
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
    get_device_proc_addr: std.meta.Child(c.PFN_vkGetDeviceProcAddr),
    dispatch: Dispatch,

    pub fn init() !Self {
        var library = try loadLibrary();
        const get_instance_proc_addr = library.lookup(
            std.meta.Child(c.PFN_vkGetInstanceProcAddr),
            "vkGetInstanceProcAddr",
        ) orelse {
            vk.log.err("Failed to load vkGetInstanceProcAddr", .{});
            return error.GetInstanceProcAddrNotFound;
        };
        const get_device_proc_addr = library.lookup(
            std.meta.Child(c.PFN_vkGetDeviceProcAddr),
            "vkGetDeviceProcAddr",
        ) orelse {
            vk.log.err("Failed to load vkGetDeviceProcAddr", .{});
            return error.GetDeviceProcAddrNotFound;
        };

        var self: Self = .{
            .handle = library,
            .get_instance_proc_addr = get_instance_proc_addr,
            .get_device_proc_addr = get_device_proc_addr,
            .dispatch = undefined,
        };
        self.dispatch = try self.load(Dispatch, null);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.handle.close();
    }

    fn loadLibrary() !std.DynLib {
        for (LibraryNames) |library_name| {
            return std.DynLib.open(library_name) catch continue;
        }
        vk.log.err("Failed to load Vulkan library", .{});
        return error.LoadLibraryFailed;
    }

    pub fn get_proc(
        self: Self,
        comptime PFN: type,
        instance: c.VkInstance,
        name: [*c]const u8,
    ) !std.meta.Child(PFN) {
        if (self.get_instance_proc_addr(instance, name)) |proc| {
            return @ptrCast(proc);
        } else {
            vk.log.err("Failed to load Vulkan proc: {s}", .{name});
            return error.GetInstanceProcAddrFailed;
        }
    }

    pub fn load(
        self: Library,
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

    pub fn createInstance(
        self: *Self,
        create_info: *const c.VkInstanceCreateInfo,
        allocation_callbacks: ?*const c.VkAllocationCallbacks,
        instance: *c.VkInstance,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan instance",
            self.dispatch.CreateInstance(create_info, allocation_callbacks, instance),
        );
    }

    pub fn enumerateInstanceExtensionProperties(
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
            vk.log.warn("Failed to enumerate Vulkan instance extension properties: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to enumerate Vulkan instance extension properties",
                result,
            );
        }
    }

    pub fn enumerateInstanceExtensionPropertiesAlloc(
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

    pub fn enumerateInstanceLayerProperties(
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
            vk.log.warn("Failed to enumerate Vulkan instance layer properties: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to enumerate Vulkan instance layer properties",
                result,
            );
        }
    }

    pub fn enumerateInstanceLayerPropertiesAlloc(
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
