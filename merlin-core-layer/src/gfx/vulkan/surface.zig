const std = @import("std");

const c = @import("../../c.zig").c;
const glfw = @import("../../platform/glfw.zig");
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
    ) !Self {
        var surface: c.VkSurfaceKHR = undefined;
        try vk.checkVulkanError(
            "Failed to create Vulkan surface",
            glfw.glfwCreateDefaultWindowSurface(
                instance.handle,
                instance.allocation_callbacks,
                &surface,
            ),
        );

        return .{
            .handle = surface,
            .dispatch = try library.load(Dispatch, instance.handle),
            .instance = instance,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatch.DestroySurfaceKHR(
            self.instance.handle,
            self.handle,
            self.instance.allocation_callbacks,
        );
    }
};
