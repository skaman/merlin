const std = @import("std");
const builtin = @import("builtin");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Surface = struct {
    const Self = @This();
    const Dispatch = struct {
        DestroySurfaceKHR: std.meta.Child(c.PFN_vkDestroySurfaceKHR) = undefined,
    };

    handle: c.VkSurfaceKHR,
    dispatch: Dispatch,
    instance: *const vk.Instance,

    pub fn init(
        library: *vk.Library,
        instance: *const vk.Instance,
        options: *const gfx.Options,
    ) !Self {
        const dispatch = try library.load(Dispatch, instance.handle);

        var surface: c.VkSurfaceKHR = undefined;
        switch (builtin.target.os.tag) {
            .windows => {
                surface = try createWin32Surface(library, instance, options);
            },
            .linux => {
                if (options.window_type == .wayland) {
                    surface = try createWaylandSurface(library, instance, options);
                } else {
                    surface = createXcbSurface(library, instance, options) catch
                        try createXlibSurface(library, instance, options);
                }
            },
            .macos => {
                surface = try createCocoaSurface(library, instance, options);
            },
            else => {
                @compileError("Unsupported OS");
            },
        }

        return .{
            .handle = surface,
            .dispatch = dispatch,
            .instance = instance,
        };
    }

    fn createWaylandSurface(
        library: *vk.Library,
        instance: *const vk.Instance,
        options: *const gfx.Options,
    ) !c.VkSurfaceKHR {
        const createWaylandSurfaceKHR = try library.get_proc(c.PFN_vkCreateWaylandSurfaceKHR, instance.handle, "vkCreateWaylandSurfaceKHR");

        vk.log.info("Creating Wayland surface", .{});

        const create_info = std.mem.zeroInit(c.VkWaylandSurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_WAYLAND_SURFACE_CREATE_INFO_KHR,
            .surface = @as(?*c.struct_wl_surface, @ptrCast(options.window)),
            .display = @as(?*c.struct_wl_display, @ptrCast(options.display)),
        });
        var surface: c.VkSurfaceKHR = undefined;
        try vk.checkVulkanError(
            "Failed to create Vulkan surface",
            createWaylandSurfaceKHR(
                instance.handle,
                &create_info,
                instance.allocation_callbacks,
                &surface,
            ),
        );
        return surface;
    }

    fn createXlibSurface(
        library: *vk.Library,
        instance: *const vk.Instance,
        options: *const gfx.Options,
    ) !c.VkSurfaceKHR {
        const createXlibSurfaceKHR = try library.get_proc(c.PFN_vkCreateXlibSurfaceKHR, instance.handle, "vkCreateXlibSurfaceKHR");

        vk.log.info("Creating Xlib surface", .{});

        const create_info = std.mem.zeroInit(c.VkXlibSurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR,
            .dpy = @as(?*c.Display, @ptrCast(options.display)),
            .window = @as(c.Window, @intCast(@intFromPtr(options.window))),
        });
        var surface: c.VkSurfaceKHR = undefined;
        try vk.checkVulkanError(
            "Failed to create Vulkan surface",
            createXlibSurfaceKHR(
                instance.handle,
                &create_info,
                instance.allocation_callbacks,
                &surface,
            ),
        );
        return surface;
    }

    fn createXcbSurface(
        library: *vk.Library,
        instance: *const vk.Instance,
        options: *const gfx.Options,
    ) !c.VkSurfaceKHR {
        const createXcbSurfaceKHR = try library.get_proc(c.PFN_vkCreateXcbSurfaceKHR, instance.handle, "vkCreateXcbSurfaceKHR");

        vk.log.info("Creating Xcb surface", .{});

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

        const connection = get_xcb_connection(@ptrCast(options.display));
        if (connection == null) {
            vk.log.err("Failed to get XCB connection", .{});
            return error.GetProcAddressFailed;
        }

        const create_info = std.mem.zeroInit(c.VkXcbSurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_XCB_SURFACE_CREATE_INFO_KHR,
            .connection = connection,
            .window = @as(c.xcb_window_t, @intCast(@intFromPtr(options.window))),
        });
        var surface: c.VkSurfaceKHR = undefined;
        try vk.checkVulkanError(
            "Failed to create Vulkan surface",
            createXcbSurfaceKHR(
                instance.handle,
                &create_info,
                instance.allocation_callbacks,
                &surface,
            ),
        );
        return surface;
    }

    fn createWin32Surface(
        library: *vk.Library,
        instance: *const vk.Instance,
        options: *const gfx.Options,
    ) !c.VkSurfaceKHR {
        const createWin32SurfaceKHR = try library.get_proc(c.PFN_vkCreateWin32SurfaceKHR, instance.handle, "vkCreateWin32SurfaceKHR");

        vk.log.info("Creating Win32 surface", .{});

        const create_info = std.mem.zeroInit(c.VkWin32SurfaceCreateInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR,
            .hinstance = @as(c.HINSTANCE, @ptrCast(options.hinstance)),
            .hwnd = @as(c.HWND, @ptrCast(options.hwnd)),
        });
        var surface: c.VkSurfaceKHR = undefined;
        try vk.checkVulkanError(
            "Failed to create Vulkan surface",
            createWin32SurfaceKHR(
                instance.handle,
                &create_info,
                instance.allocation_callbacks,
                &surface,
            ),
        );
        return surface;
    }

    fn createCocoaSurface(
        library: *vk.Library,
        instance: *const vk.Instance,
        options: *const gfx.Options,
    ) !c.VkSurfaceKHR {
        const createMacOSSurfaceMVK = try library.get_proc(c.PFN_vkCreateMacOSSurfaceMVK, instance.handle, "vkCreateMacOSSurfaceMVK");

        vk.log.info("Creating Cocoa surface", .{});

        const create_info = std.mem.zeroInit(c.VkMacOSSurfaceCreateInfoMVK, .{
            .sType = c.VK_STRUCTURE_TYPE_MACOS_SURFACE_CREATE_INFO_MVK,
            .pView = @as(?*c.id, @ptrCast(options.view)),
        });
        var surface: c.VkSurfaceKHR = undefined;
        try vk.checkVulkanError(
            "Failed to create Vulkan surface",
            createMacOSSurfaceMVK(
                instance.handle,
                &create_info,
                instance.allocation_callbacks,
                &surface,
            ),
        );
        return surface;
    }

    pub fn deinit(self: *Self) void {
        self.dispatch.DestroySurfaceKHR(
            self.instance.handle,
            self.handle,
            self.instance.allocation_callbacks,
        );
    }
};
