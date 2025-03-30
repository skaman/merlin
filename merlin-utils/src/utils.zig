const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");

pub const gfx_types = @import("gfx_types.zig");
pub const loaders = @import("loaders.zig");

const dbg = builtin.mode == std.builtin.Mode.Debug;

pub fn HandlePool(comptime THandle: type, comptime size: comptime_int) type {
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
                self.free_list[i] = @intCast((size - 1) - i);
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.free_count == size);
        }

        pub fn alloc(self: *Self) !THandle {
            if (self.free_count == 0) {
                return error.NoAvailableHandles;
            }

            self.free_count -= 1;
            return self.free_list[self.free_count];
        }

        pub fn free(self: *Self, handle: THandle) void {
            if (dbg) {
                for (self.free_list[0..self.free_count]) |h| {
                    std.debug.assert(h != handle);
                }
            }

            self.free_list[self.free_count] = handle;
            self.free_count += 1;
        }

        pub fn clear(self: *Self) void {
            self.free_count = size;
        }
    };
}

// From https://codeberg.org/hDS9HQLN/ztsl
pub const Serializer = struct {
    pub const HeaderSize = @sizeOf(u32) + @sizeOf(u8);
    pub const Endian = std.builtin.Endian.little;

    pub fn writeHeader(writer: anytype, magic: u32, version: u8) !void {
        try writer.writeInt(u32, magic, Endian);
        try writer.writeByte(version);
    }

    pub fn write(writer: anytype, data: anytype) !void {
        const T = @TypeOf(data);
        switch (@typeInfo(T)) {
            .@"struct" => |s| {
                inline for (s.fields) |field| {
                    try write(writer, @field(data, field.name));
                }
            },
            .@"union" => |u| {
                const E = u.tag_type orelse
                    @compileError(std.fmt.comptimePrint("Union {s} has to tag type.", .{@typeName(T)}));
                try write(writer, @as(E, data));
                switch (data) {
                    inline else => |f| try write(writer, f),
                }
            },
            .@"enum" => try write(writer, @intFromEnum(data)),
            .pointer => |p| switch (p.size) {
                .one => try write(writer, data.*),
                .slice => {
                    try write(writer, data.len);
                    if (@sizeOf(p.child) == 1) {
                        try writer.writeAll(@ptrCast(data));
                    } else {
                        for (data) |e|
                            try write(writer, e);
                    }
                },
                .many, .c => @compileError(std.fmt.comptimePrint("Unhandled type: {}", .{T})),
            },
            .int => try writer.writeInt(T, data, Endian),
            .float => {
                const float_size = @sizeOf(T);
                if (float_size == 4) {
                    try writer.writeInt(u32, @bitCast(data), Endian);
                } else if (float_size == 8) {
                    try writer.writeInt(u64, @bitCast(data), Endian);
                } else {
                    @compileError(std.fmt.comptimePrint("Unhandled float size: {}", .{float_size}));
                }
            },
            .void => {},
            .bool => try writer.writeByte(@intFromBool(data)),
            .array => |a| if (@sizeOf(a.child) == 1) {
                try writer.writeAll(@ptrCast(&data));
            } else {
                for (data) |e|
                    try write(writer, e);
            },
            .optional => if (data) |data_value| {
                try write(writer, true);
                try write(writer, data_value);
            } else {
                try write(writer, false);
            },
            else => @compileError(std.fmt.comptimePrint("Unhandled type: {}", .{T})),
        }
    }

    pub fn checkHeader(reader: anytype, magic: u32, version: u8) !void {
        if (try reader.readInt(u32, Endian) != magic) {
            return error.InvalidMagic;
        }

        if (try reader.readByte() != version) {
            return error.InvalidVersion;
        }
    }

    pub fn read(T: type, allocator: std.mem.Allocator, reader: anytype) !T {
        return switch (@typeInfo(T)) {
            .@"struct" => |s| b: {
                var data: T = undefined;
                inline for (s.fields) |f|
                    @field(data, f.name) = try read(f.type, allocator, reader);
                break :b data;
            },
            .@"union" => |u| switch (try read(u.tag_type.?, allocator, reader)) {
                inline else => |t| b: {
                    var data: T = @unionInit(T, @tagName(t), undefined);
                    const field = &@field(data, @tagName(t));
                    field.* = try read(@TypeOf(field.*), allocator, reader);
                    break :b data;
                },
            },
            .@"enum" => |e| @enumFromInt(try read(e.tag_type, allocator, reader)),
            .pointer => |p| switch (p.size) {
                .one => b: {
                    const ptr = try allocator.create(p.child);
                    errdefer allocator.destroy(ptr);
                    ptr.* = try read(p.child, allocator, reader);
                    break :b ptr;
                },
                .slice => b: {
                    const slice = try allocator.alignedAlloc(p.child, @alignOf(T), try read(usize, allocator, reader));
                    errdefer allocator.free(slice);
                    if (@sizeOf(p.child) == 1) {
                        try reader.readNoEof(slice);
                    } else {
                        for (slice) |*e|
                            e.* = try read(p.child, allocator, reader);
                    }
                    break :b slice;
                },
                .many, .c => @compileError(std.fmt.comptimePrint("Unhandled type: {}", .{T})),
            },
            .int => @intCast(try reader.readInt(T, Endian)),
            .float => {
                const float_size = @sizeOf(T);
                if (float_size == 4) {
                    return @as(T, @bitCast(try reader.readInt(u32, Endian)));
                } else if (float_size == 8) {
                    return @as(T, @bitCast(try reader.readInt(u64, Endian)));
                } else {
                    @compileError(std.fmt.comptimePrint("Unhandled float size: {}", .{float_size}));
                }
            },
            .void => {},
            .bool => try reader.readByte() == 1,
            .array => |a| b: {
                var array: T = undefined;
                if (@sizeOf(a.child) == 1) {
                    try reader.readNoEof(&array);
                } else {
                    for (&array) |*e|
                        e.* = try read(a.child, allocator, reader);
                }
                break :b array;
            },
            .optional => |o| if (try read(bool, allocator, reader))
                try read(o.child, allocator, reader)
            else
                null,
            else => @compileError(std.fmt.comptimePrint("Unhandled type: {}", .{T})),
        };
    }
};

inline fn toBytes(num: anytype) []const u8 {
    return &@as([@sizeOf(@TypeOf(num))]u8, @bitCast(num));
}

const TestEnum = enum(u16) { a, b, c };

const TestStruct2 = struct {
    a: []const u8,
};

const TestStruct = struct {
    a: u32,
    b: u16,
    c: TestEnum,
    d: bool,
    e: ?TestStruct2,
};

test "binary serialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const test_struct = TestStruct{
        .a = 42,
        .b = 8,
        .c = .b,
        .d = true,
        .e = .{ .a = std.mem.sliceTo("HELLO", 0) },
    };

    var array_list = std.ArrayList(u8).init(gpa.allocator());
    defer array_list.deinit();

    try Serializer.write(array_list.writer(), test_struct);

    //for (array_list.items) |item| {
    //    std.debug.print("{}, ", .{item});
    //}

    const expected = &[_]u8{ 42, 0, 0, 0, 8, 0, 1, 0, 1, 1, 5, 0, 0, 0, 0, 0, 0, 0, 72, 69, 76, 76, 79 };
    try expect(std.mem.eql(u8, array_list.items, expected));
}

test "binary deserialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const data = &[_]u8{ 42, 0, 0, 0, 8, 0, 1, 0, 1, 1, 5, 0, 0, 0, 0, 0, 0, 0, 72, 69, 76, 76, 79 };
    var stream = std.io.fixedBufferStream(data);

    const allocator = gpa.allocator();
    const result = try Serializer.read(TestStruct, allocator, stream.reader());
    defer allocator.free(result.e.?.a);

    try expect(result.a == 42);
    try expect(result.b == 8);
    try expect(result.c == .b);
    try expect(result.d == true);
    try expect(result.e != null);
    try expect(std.mem.eql(u8, result.e.?.a, std.mem.sliceTo("HELLO", 0)));
}
