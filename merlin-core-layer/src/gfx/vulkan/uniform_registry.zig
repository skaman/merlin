const std = @import("std");

const c = @import("../../c.zig").c;
const utils = @import("../../utils.zig");
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const UniformRegistry = struct {
    const Self = @This();

    pub const UniformBufferEntry = struct {
        name: []const u8,
        buffer: [vk.MaxFramesInFlight]vk.UniformBuffer,
        buffer_count: u32,
        buffer_size: u32,
        ref_count: u32,
    };

    pub const UniformCombinedSamplerEntry = struct {
        name: []const u8,
        texture: ?gfx.TextureHandle,
        ref_count: u32,
    };

    pub const UniformEntry = union(gfx.DescriptorBindType) {
        uniform: UniformBufferEntry,
        combined_sampler: UniformCombinedSamplerEntry,
    };

    allocator: std.mem.Allocator,
    name_map: std.StringHashMap(gfx.UniformHandle),
    entries: [gfx.MaxUniformHandles]UniformEntry,
    handles: utils.HandlePool(gfx.UniformHandle, gfx.MaxUniformHandles),

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .allocator = allocator,
            .name_map = .init(allocator),
            .handles = .init(),
            .entries = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        // TODO: check for memory leaks
        self.name_map.deinit();
        self.handles.deinit();
    }

    pub fn createBuffer(
        self: *Self,
        name: []const u8,
        size: u32,
    ) !gfx.UniformHandle {
        const existing_handle = self.name_map.get(name);
        if (existing_handle) |value| {
            self.entries[value].uniform.ref_count += 1;
            return value;
        }

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const handle = try self.handles.alloc();
        errdefer self.handles.free(handle);

        try self.name_map.put(name_copy, handle);
        errdefer _ = self.name_map.remove(name_copy);

        var buffer_count: u32 = 0;
        var buffer: [vk.MaxFramesInFlight]vk.UniformBuffer = undefined;

        errdefer {
            for (0..buffer_count) |i| {
                buffer[i].deinit();
            }
        }
        inline for (0..vk.MaxFramesInFlight) |i| {
            buffer[i] = try vk.UniformBuffer.init(size);
            buffer_count += 1;
        }

        self.entries[handle] = UniformEntry{
            .uniform = UniformBufferEntry{
                .name = name_copy,
                .buffer = buffer,
                .buffer_count = buffer_count,
                .buffer_size = size,
                .ref_count = 1,
            },
        };

        vk.log.debug("Created uniform buffer:", .{});
        vk.log.debug("  - Name: {s}", .{name});
        vk.log.debug("  - Size: {s}", .{std.fmt.fmtIntSizeDec(size)});

        return handle;
    }

    pub fn updateBuffer(
        self: *Self,
        handle: gfx.UniformHandle,
        frame_index: u32,
        data: []const u8,
    ) !void {
        const entry = &self.entries[handle];
        switch (entry.*) {
            .uniform => {
                var uniform = &entry.uniform;
                std.debug.assert(frame_index < uniform.buffer_count);
                uniform.buffer[frame_index].update(data);
            },
            else => {
                vk.log.err("Uniform handle is not a buffer", .{});
                return error.UniformHandleIsNotABuffer;
            },
        }
    }

    pub fn createCombinedSampler(
        self: *Self,
        name: []const u8,
    ) !gfx.UniformHandle {
        const existing_handle = self.name_map.get(name);
        if (existing_handle) |value| {
            self.entries[value].combined_sampler.ref_count += 1;
            return value;
        }

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        const handle = try self.handles.alloc();
        errdefer self.handles.free(handle);

        try self.name_map.put(name_copy, handle);
        errdefer _ = self.name_map.remove(name_copy);

        self.entries[handle] = UniformEntry{
            .combined_sampler = UniformCombinedSamplerEntry{
                .name = name_copy,
                .texture = null,
                .ref_count = 1,
            },
        };

        vk.log.debug("Created combined sampler:", .{});
        vk.log.debug("  - Name: {s}", .{name});

        return handle;
    }

    pub fn updateCombinedSampler(
        self: *Self,
        handle: gfx.UniformHandle,
        texture: gfx.TextureHandle,
    ) !void {
        const entry = &self.entries[handle];
        switch (entry.*) {
            .combined_sampler => {
                entry.combined_sampler.texture = texture;
            },
            else => {
                vk.log.err("Uniform handle is not a combined sampler", .{});
                return error.UniformHandleIsNotACombinedSampler;
            },
        }
    }

    pub fn destroy(self: *Self, handle: gfx.UniformHandle) void {
        switch (self.entries[handle]) {
            .uniform => |*uniform| {
                std.debug.assert(uniform.ref_count > 0);

                uniform.ref_count -= 1;

                if (self.entries[handle].uniform.ref_count == 0) {
                    vk.log.debug("Destroyed uniform buffer:", .{});
                    vk.log.debug("  - Name: {s}", .{uniform.name});

                    _ = self.name_map.remove(uniform.name);
                    self.allocator.free(uniform.name);

                    for (0..uniform.buffer_count) |i| {
                        uniform.buffer[i].deinit();
                    }

                    self.handles.free(handle);
                }
            },
            .combined_sampler => |*combined_sampler| {
                std.debug.assert(combined_sampler.ref_count > 0);

                combined_sampler.ref_count -= 1;

                if (self.entries[handle].combined_sampler.ref_count == 0) {
                    vk.log.debug("Destroyed combined sampler:", .{});
                    vk.log.debug("  - Name: {s}", .{combined_sampler.name});

                    _ = self.name_map.remove(combined_sampler.name);
                    self.allocator.free(combined_sampler.name);

                    self.handles.free(handle);
                }
            },
        }
    }

    //pub fn get(self: *Self, name: []const u8) !*Entry {
    //    return self.entries.get(name);
    //}
};
