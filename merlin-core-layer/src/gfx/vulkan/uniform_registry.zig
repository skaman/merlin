const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const UniformRegistry = struct {
    const Self = @This();

    pub const Entry = struct {
        name: []const u8,
        size: u32,
        buffer: [vk.MaxFramesInFlight]vk.UniformBuffer,
        buffer_count: u32,
        ref_count: u32,
    };

    allocator: std.mem.Allocator,
    device: *const vk.Device,
    entries: std.StringHashMap(*Entry),

    pub fn init(
        allocator: std.mem.Allocator,
        device: *const vk.Device,
    ) !Self {
        return .{
            .allocator = allocator,
            .device = device,
            .entries = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit();
    }

    pub fn create(
        self: *Self,
        name: []const u8,
        size: u32,
    ) !*Entry {
        var existing_entry = self.entries.get(name);
        if (existing_entry != null) {
            existing_entry.?.ref_count += 1;
            return existing_entry.?;
        }

        var entry = try self.allocator.create(Entry);
        errdefer self.allocator.destroy(entry);

        entry.name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(entry.name);

        entry.size = size;
        entry.buffer_count = 0;

        errdefer {
            for (0..entry.buffer_count) |i| {
                entry.buffer[i].deinit();
            }
        }
        inline for (0..vk.MaxFramesInFlight) |i| {
            entry.buffer[i] = try vk.UniformBuffer.init(self.device, size);
            entry.buffer_count += 1;
        }

        entry.ref_count = 1;
        try self.entries.put(name, entry);

        vk.log.debug("Created uniform buffer:", .{});
        vk.log.debug("  - Name: {s}", .{name});
        vk.log.debug("  - Size: {s}", .{std.fmt.fmtIntSizeDec(size)});

        return self.entries.get(name).?;
    }

    pub fn destroy(self: *Self, name: []const u8) void {
        var entry = self.entries.get(name);
        if (entry == null) return;

        entry.?.ref_count -= 1;
        if (entry.?.ref_count == 0) {
            vk.log.debug("Destroyed uniform buffer:", .{});
            vk.log.debug("  - Name: {s}", .{name});

            _ = self.entries.remove(name);
            self.allocator.free(entry.?.name);

            for (0..entry.?.buffer_count) |i| {
                entry.?.buffer[i].deinit();
            }
            self.allocator.destroy(entry.?);
        }
    }

    pub fn get(self: *Self, name: []const u8) !*Entry {
        return self.entries.get(name);
    }
};
