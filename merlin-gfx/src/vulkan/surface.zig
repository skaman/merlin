const std = @import("std");
const builtin = @import("builtin");

const platform = @import("merlin_platform");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

const Dispatch = struct {
    DestroySurfaceKHR: std.meta.Child(c.PFN_vkDestroySurfaceKHR) = undefined,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var dispatch: ?Dispatch = null;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn createWaylandSurface() !c.VkSurfaceKHR {
    const createWaylandSurfaceKHR = try vk.library.get_proc(
        c.PFN_vkCreateWaylandSurfaceKHR,
        vk.instance.handle,
        "vkCreateWaylandSurfaceKHR",
    );

    vk.log.debug("Creating Wayland surface", .{});

    const create_info = std.mem.zeroInit(c.VkWaylandSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
        .surface = @as(?*c.struct_wl_surface, @ptrCast(platform.getNativeDefaultWindowHandle())),
        .display = @as(?*c.struct_wl_display, @ptrCast(platform.getNativeDisplayHandle())),
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

fn createXlibSurface() !c.VkSurfaceKHR {
    const createXlibSurfaceKHR = try vk.library.get_proc(
        c.PFN_vkCreateXlibSurfaceKHR,
        vk.instance.handle,
        "vkCreateXlibSurfaceKHR",
    );

    vk.log.debug("Creating Xlib surface", .{});

    const create_info = std.mem.zeroInit(c.VkXlibSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
        .window = @as(c.Window, @intCast(@intFromPtr(platform.getNativeDefaultWindowHandle()))),
        .dpy = @as(?*c.Display, @ptrCast(platform.getNativeDisplayHandle())),
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

fn createXcbSurface() !c.VkSurfaceKHR {
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

    const connection = get_xcb_connection(@ptrCast(platform.getNativeDisplayHandle()));
    if (connection == null) {
        vk.log.err("Failed to get XCB connection", .{});
        return error.GetProcAddressFailed;
    }

    const create_info = std.mem.zeroInit(c.VkXcbSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
        .connection = connection,
        .window = @as(c.xcb_window_t, @intCast(@intFromPtr(platform.getNativeDefaultWindowHandle()))),
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

fn createWin32Surface() !c.VkSurfaceKHR {
    const createWin32SurfaceKHR = try vk.library.get_proc(
        c.PFN_vkCreateWin32SurfaceKHR,
        vk.instance.handle,
        "vkCreateWin32SurfaceKHR",
    );

    vk.log.debug("Creating Win32 surface", .{});

    const create_info = std.mem.zeroInit(c.VkWin32SurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .hwnd = @as(c.HWND, @ptrCast(platform.getNativeDefaultWindowHandle())),
        .hinstance = @as(c.HINSTANCE, @ptrCast(platform.getNativeDisplayHandle())),
    });
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

fn createCocoaSurface() !c.VkSurfaceKHR {
    const createMacOSSurfaceMVK = try vk.library.get_proc(
        c.PFN_vkCreateMacOSSurfaceMVK,
        vk.instance.handle,
        "vkCreateMacOSSurfaceMVK",
    );

    vk.log.debug("Creating Cocoa surface", .{});

    const create_info = std.mem.zeroInit(c.VkMacOSSurfaceCreateInfoMVK, .{
        .sType = c.VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK,
        .pView = @as(?*c.id, @ptrCast(platform.getNativeDefaultWindowHandle())),
    });
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

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn create() !c.VkSurfaceKHR {
    if (dispatch == null) {
        dispatch = try vk.library.load(Dispatch, vk.instance.handle);
    }

    var surface: c.VkSurfaceKHR = undefined;
    switch (builtin.target.os.tag) {
        .windows => {
            surface = try createWin32Surface();
        },
        .linux => {
            if (platform.getNativeWindowHandleType() == .wayland) {
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

pub fn destroy(surface: c.VkSurfaceKHR) void {
    std.debug.assert(dispatch != null);
    dispatch.?.DestroySurfaceKHR(
        vk.instance.handle,
        surface,
        vk.instance.allocation_callbacks,
    );
}
