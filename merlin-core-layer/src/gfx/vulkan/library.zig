const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const vk = @import("vulkan.zig");

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

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var get_instance_proc_addr: std.meta.Child(c.PFN_vkGetInstanceProcAddr) = undefined;
pub var get_device_proc_addr: std.meta.Child(c.PFN_vkGetDeviceProcAddr) = undefined;

var handle: std.DynLib = undefined;
var dispatch: Dispatch = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn loadLibrary() !std.DynLib {
    for (LibraryNames) |library_name| {
        return std.DynLib.open(library_name) catch continue;
    }
    vk.log.err("Failed to load Vulkan library", .{});
    return error.LoadLibraryFailed;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() !void {
    handle = try loadLibrary();

    get_instance_proc_addr = handle.lookup(
        std.meta.Child(c.PFN_vkGetInstanceProcAddr),
        "vkGetInstanceProcAddr",
    ) orelse {
        vk.log.err("Failed to load vkGetInstanceProcAddr", .{});
        return error.GetInstanceProcAddrNotFound;
    };

    get_device_proc_addr = handle.lookup(
        std.meta.Child(c.PFN_vkGetDeviceProcAddr),
        "vkGetDeviceProcAddr",
    ) orelse {
        vk.log.err("Failed to load vkGetDeviceProcAddr", .{});
        return error.GetDeviceProcAddrNotFound;
    };

    dispatch = try load(Dispatch, null);
}

pub fn deinit() void {
    handle.close();
}

pub fn get_proc(
    comptime PFN: type,
    instance: c.VkInstance,
    name: [*c]const u8,
) !std.meta.Child(PFN) {
    if (get_instance_proc_addr(instance, name)) |proc| {
        return @ptrCast(proc);
    } else {
        vk.log.err("Failed to load Vulkan proc: {s}", .{name});
        return error.GetInstanceProcAddrFailed;
    }
}

pub fn load(
    comptime TDispatch: type,
    instance: c.VkInstance,
) !TDispatch {
    var tdispatch = TDispatch{};
    inline for (@typeInfo(TDispatch).@"struct".fields) |field| {
        @field(tdispatch, field.name) = try get_proc(
            ?field.type,
            instance,
            "vk" ++ field.name,
        );
    }
    return tdispatch;
}

pub fn createInstance(
    create_info: *const c.VkInstanceCreateInfo,
    allocation_callbacks: ?*const c.VkAllocationCallbacks,
    instance: *c.VkInstance,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan instance",
        dispatch.CreateInstance(create_info, allocation_callbacks, instance),
    );
}

pub fn enumerateInstanceExtensionProperties(
    layer_name: [*c]const u8,
    count: *u32,
    properties: [*c]c.VkExtensionProperties,
) !void {
    const result = dispatch.EnumerateInstanceExtensionProperties(
        layer_name,
        count,
        properties,
    );
    try vk.checkVulkanError(
        "Failed to enumerate Vulkan instance extension properties",
        result,
    );
}

pub fn enumerateInstanceExtensionPropertiesAlloc(
    allocator: std.mem.Allocator,
    layer_name: [*c]const u8,
) ![]c.VkExtensionProperties {
    var count: u32 = undefined;
    try enumerateInstanceExtensionProperties(
        layer_name,
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkExtensionProperties,
        count,
    );
    errdefer allocator.free(result);

    try enumerateInstanceExtensionProperties(
        layer_name,
        &count,
        result.ptr,
    );
    return result;
}

pub fn enumerateInstanceLayerProperties(
    count: *u32,
    properties: [*c]c.VkLayerProperties,
) !void {
    const result = dispatch.EnumerateInstanceLayerProperties(
        count,
        properties,
    );
    try vk.checkVulkanError(
        "Failed to enumerate Vulkan instance layer properties",
        result,
    );
}

pub fn enumerateInstanceLayerPropertiesAlloc(allocator: std.mem.Allocator) ![]c.VkLayerProperties {
    var count: u32 = undefined;
    try enumerateInstanceLayerProperties(
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkLayerProperties,
        count,
    );
    errdefer allocator.free(result);

    try enumerateInstanceLayerProperties(
        &count,
        result.ptr,
    );
    return result;
}
