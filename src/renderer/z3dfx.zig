const std = @import("std");

const c = @import("../c.zig");
const noop = @import("noop.zig");
const vulkan = @import("vulkan.zig");

pub const RendererType = enum {
    noop,
    vulkan,
};

pub const Renderer = struct {
    const Self = @This();

    ptr: *anyopaque,
    vtab: *const VTab,
    const VTab = struct {
        deinit: *const fn (*anyopaque) void,
    };

    fn init(ptr: anytype) Self {
        const Ptr = @TypeOf(ptr);
        const impl = struct {
            fn deinit(ptr_: *anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr_));
                self.deinit();
            }
        };
        return .{
            .ptr = ptr,
            .vtab = &.{
                .deinit = impl.deinit,
            },
        };
    }

    fn deinit(self: Self) void {
        self.vtab.deinit(self.ptr);
    }
};

pub const InitArgs = struct {
    renderer_type: RendererType,
    app_name: [:0]const u8,
    window: *c.glfw.GLFWwindow,
};

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    renderer_type: RendererType,
    renderer: Renderer,

    pub fn deinit(self: *const Self) void {
        self.renderer.deinit();
    }
};

var context: Context = undefined;

pub fn init(allocator: std.mem.Allocator, args: InitArgs) !void {
    std.log.debug("Initializing renderer...", .{});

    const renderer = try createRenderer(allocator, &args);
    errdefer renderer.deinit();

    context = .{
        .allocator = allocator,
        .renderer = renderer,
        .renderer_type = args.renderer_type,
    };
}

pub fn deinit() void {
    std.log.debug("Deinitializing renderer...", .{});
    context.deinit();
    //destroyRenderer(&context.renderer);
}

fn createRenderer(allocator: std.mem.Allocator, args: *const InitArgs) !Renderer {
    switch (args.renderer_type) {
        RendererType.noop => {
            const noop_renderer = try allocator.create(noop.NoopRenderer);
            return Renderer.init(noop_renderer);
        },
        RendererType.vulkan => {
            const vulkan_renderer = try allocator.create(vulkan.VulkanRenderer);
            vulkan_renderer.* = try .init(allocator, args);
            return Renderer.init(vulkan_renderer);
        },
    }
}
