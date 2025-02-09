const std = @import("std");

const c = @import("../c.zig").c;
const noop = @import("noop.zig");
const vulkan = @import("vulkan.zig");

pub const GraphicsContext = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: GraphicsOptions,

    pub fn deinit(self: *const Self) void {
        _ = self;
    }
};

pub const GraphicsOptions = struct {
    renderer_type: RendererType,
    app_name: [:0]const u8,
    window: *c.GLFWwindow,

    enable_vulkan_debug: bool = false,
};

pub const RendererType = enum {
    noop,
    vulkan,
};

pub const Handle = u16;
pub const ShaderHandle = Handle;

pub const MaxShaderHandles = 512;

fn HandlePool(comptime THandle: type, comptime size: comptime_int) type {
    return struct {
        const Self = @This();

        free_list: [size]THandle,
        free_count: u32 = size,

        pub fn init() Self {
            var self: Self = .{
                .free_list = undefined,
                .free_count = size,
            };

            for (0..size) |i| {
                self.free_list[i] = @intCast(i);
            }

            return self;
        }

        pub fn alloc(self: *Self) !THandle {
            if (self.free_count == 0) {
                return error.NoAvailableHandles;
            }

            self.free_count -= 1;
            return self.free_list[self.free_count];
        }

        pub fn free(self: *Self, handle: THandle) void {
            self.free_list[self.free_count] = handle;
            self.free_count += 1;
        }
    };
}

pub const Renderer = struct {
    const Self = @This();
    const VTab = struct {
        deinit: *const fn (*anyopaque) void,
        createShader: *const fn (*anyopaque, handle: ShaderHandle, []align(@alignOf(u32)) const u8) anyerror!void,
        destroyShader: *const fn (*anyopaque, handle: ShaderHandle) void,
    };

    ptr: *anyopaque,
    vtab: *const VTab,

    fn init(ptr: anytype) Self {
        const Ptr = @TypeOf(ptr);
        const impl = struct {
            fn deinit(ptr_: *anyopaque) void {
                const self: Ptr = @ptrCast(@alignCast(ptr_));
                self.deinit();
            }
            fn createShader(ptr_: *anyopaque, handle: ShaderHandle, data: []align(@alignOf(u32)) const u8) anyerror!void {
                const self: Ptr = @ptrCast(@alignCast(ptr_));
                return self.createShader(handle, data);
            }
            fn destroyShader(ptr_: *anyopaque, handle: ShaderHandle) void {
                const self: Ptr = @ptrCast(@alignCast(ptr_));
                self.destroyShader(handle);
            }
        };
        return .{
            .ptr = ptr,
            .vtab = &.{
                .deinit = impl.deinit,
                .createShader = impl.createShader,
                .destroyShader = impl.destroyShader,
            },
        };
    }

    fn deinit(self: Self) void {
        self.vtab.deinit(self.ptr);
    }

    fn createShader(self: *Self, handle: ShaderHandle, data: []align(@alignOf(u32)) const u8) !void {
        return self.vtab.createShader(self.ptr, handle, data);
    }

    fn destroyShader(self: *Self, handle: ShaderHandle) void {
        return self.vtab.destroyShader(self.ptr, handle);
    }
};

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    renderer_type: RendererType,
    renderer: Renderer,

    shader_handles: HandlePool(ShaderHandle, MaxShaderHandles),

    pub fn deinit(self: *const Self) void {
        self.renderer.deinit();
    }
};

var context: Context = undefined;

pub fn init(
    allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    options: GraphicsOptions,
) !void {
    std.log.debug("Initializing renderer...", .{});

    const graphics_context = GraphicsContext{
        .allocator = allocator,
        .arena_allocator = arena_allocator,
        .options = options,
    };

    const renderer = try createRenderer(&graphics_context);
    errdefer renderer.deinit();

    context = .{
        .allocator = allocator,
        .arena_allocator = arena_allocator,
        .renderer = renderer,
        .renderer_type = options.renderer_type,
        .shader_handles = .init(),
    };
}

pub fn deinit() void {
    std.log.debug("Deinitializing renderer...", .{});
    context.deinit();
}

pub fn createShader(data: []align(@alignOf(u32)) const u8) !ShaderHandle {
    const handle = try context.shader_handles.alloc();
    errdefer context.shader_handles.free(handle);

    try context.renderer.createShader(handle, data);
    return handle;
}

pub fn createShaderUnaligned(data: []const u8) !ShaderHandle {
    const aligned_data = try context.arena_allocator.alignedAlloc(
        u8,
        @alignOf(u32),
        data.len,
    );
    std.mem.copyForwards(u8, aligned_data, data);
    return try createShader(aligned_data);
}

pub fn destroyShader(handle: ShaderHandle) void {
    context.renderer.destroyShader(handle);
    context.shader_handles.free(handle);
}

fn createRenderer(
    graphics_ctx: *const GraphicsContext,
) !Renderer {
    switch (graphics_ctx.options.renderer_type) {
        RendererType.noop => {
            const noop_renderer = try graphics_ctx.allocator.create(noop.NoopRenderer);
            return Renderer.init(noop_renderer);
        },
        RendererType.vulkan => {
            const vulkan_renderer = try graphics_ctx.allocator.create(vulkan.VulkanRenderer);
            vulkan_renderer.* = try .init(graphics_ctx);
            return Renderer.init(vulkan_renderer);
        },
    }
}
