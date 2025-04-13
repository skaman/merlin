const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Globals
// *********************************************************************************************

var debug_messenger: ?c.VkDebugUtilsMessengerEXT = null;

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(options: *const gfx.Options) !void {
    if (!options.enable_vulkan_debug) {
        return;
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

    var debug_utils_messenger: c.VkDebugUtilsMessengerEXT = undefined;
    try vk.instance.createDebugUtilsMessengerEXT(
        &create_info,
        &debug_utils_messenger,
    );
    debug_messenger = debug_utils_messenger;
}

pub fn deinit() void {
    if (debug_messenger) |messenger| {
        vk.instance.destroyDebugUtilsMessengerEXT(messenger);
        debug_messenger = null;
    }
}

pub fn setObjectName(object_type: c.VkObjectType, object_handle: anytype, name: []const u8) !void {
    if (debug_messenger == null) {
        return;
    }

    const object_name_info = std.mem.zeroInit(
        c.VkDebugUtilsObjectNameInfoEXT,
        .{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
            .objectType = object_type,
            .objectHandle = @intFromPtr(object_handle),
            .pObjectName = try vk.arena.dupeZ(u8, name),
        },
    );

    try vk.instance.setDebugUtilsObjectNameEXT(vk.device.handle, &object_name_info);
}

pub fn beginCommandBufferLabel(
    command_buffer: c.VkCommandBuffer,
    label_name: []const u8,
    color: [4]f32,
) void {
    if (debug_messenger == null) {
        return;
    }

    const label_name_z = vk.arena.dupeZ(u8, label_name) catch |err| {
        vk.log.err("Failed to dupe label name: {}", .{err});
        return;
    };

    const label_info = std.mem.zeroInit(
        c.VkDebugUtilsLabelEXT,
        .{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT,
            .pLabelName = label_name_z,
            .color = color,
        },
    );

    vk.instance.cmdBeginDebugUtilsLabelEXT(command_buffer, &label_info);
}

pub fn endCommandBufferLabel(command_buffer: c.VkCommandBuffer) void {
    if (debug_messenger == null) {
        return;
    }

    vk.instance.cmdEndDebugUtilsLabelEXT(command_buffer);
}

pub fn insertCommandBufferLabel(
    command_buffer: c.VkCommandBuffer,
    label_name: []const u8,
    color: [4]f32,
) void {
    if (debug_messenger == null) {
        return;
    }

    const label_name_z = vk.arena.dupeZ(u8, label_name) catch |err| {
        vk.log.err("Failed to dupe label name: {}", .{err});
        return;
    };

    const label_info = std.mem.zeroInit(
        c.VkDebugUtilsLabelEXT,
        .{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT,
            .pLabelName = label_name_z,
            .color = color,
        },
    );

    vk.instance.cmdInsertDebugUtilsLabelEXT(command_buffer, &label_info);
}

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
        vk.log.err("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        vk.log.warn("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
        vk.log.info("{s}", .{p_callback_data.*.pMessage});
    } else if (message_severity & c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT == c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT) {
        vk.log.debug("{s}", .{p_callback_data.*.pMessage});
    }

    return c.VK_FALSE;
}
