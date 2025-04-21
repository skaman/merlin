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
        .surface = @as(?*c.struct_wl_surface, @ptrCast(platform.nativeWindowHandle(vk.main_window_handle))),
        .display = @as(?*c.struct_wl_display, @ptrCast(platform.nativeDisplayHandle())),
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
        .window = @as(c.Window, @intCast(@intFromPtr(platform.nativeWindowHandle(vk.main_window_handle)))),
        .dpy = @as(?*c.Display, @ptrCast(platform.nativeDisplayHandle())),
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

    const connection = get_xcb_connection(@ptrCast(platform.nativeDisplayHandle()));
    if (connection == null) {
        vk.log.err("Failed to get XCB connection", .{});
        return error.GetProcAddressFailed;
    }

    const create_info = std.mem.zeroInit(c.VkXcbSurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
        .connection = connection,
        .window = @as(c.xcb_window_t, @intCast(@intFromPtr(platform.nativeWindowHandle(vk.main_window_handle)))),
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
    const createWin32SurfaceKHR = try vk.library.get_proc(
        PFN_vkCreateWin32SurfaceKHR,
        vk.instance.handle,
        "vkCreateWin32SurfaceKHR",
    );

    vk.log.debug("Creating Win32 surface", .{});

    const window_handle = platform.nativeWindowHandle(vk.main_window_handle);
    const create_info = std.mem.zeroInit(struct_VkWin32SurfaceCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
        .hwnd = window_handle,
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
        .pView = @as(?*c.id, @ptrCast(platform.nativeDefaultWindowHandle())),
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

pub fn destroy(surface: c.VkSurfaceKHR) void {
    std.debug.assert(dispatch != null);
    dispatch.?.DestroySurfaceKHR(
        vk.instance.handle,
        surface,
        vk.instance.allocation_callbacks,
    );
}
