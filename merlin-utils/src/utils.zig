const std = @import("std");
const expect = std.testing.expect;
const builtin = @import("builtin");

pub const asset_types = @import("asset_types.zig");
pub const gfx_types = @import("gfx_types.zig");

pub fn HandlePool(comptime THandle: type, comptime size: comptime_int) type {
    return struct {
        const Self = @This();
        free_list: [size]THandle,
        free_count: u32 = size,
        mutex: std.Thread.Mutex,

        pub fn init() Self {
            var self: Self = .{
                .free_list = undefined,
                .free_count = size,
                .mutex = .{},
            };

            for (0..size) |i| {
                self.free_list[i] = @enumFromInt((size - 1) - i);
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.free_count == size);
        }

        pub fn create(self: *Self) THandle {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.free_count -= 1;
            return self.free_list[self.free_count];
        }

        pub fn destroy(self: *Self, handle: THandle) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.free_list[self.free_count] = handle;
            self.free_count += 1;
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.free_count = size;
        }
    };
}

pub fn HandleArray(comptime THandle: type, comptime TData: type, comptime size: comptime_int) type {
    return struct {
        const Self = @This();
        data: [size]TData,

        pub fn value(self: *Self, handle: THandle) TData {
            const index: usize = @intFromEnum(handle);
            std.debug.assert(index < size);

            return self.data[index];
        }

        pub fn valuePtr(self: *Self, handle: THandle) *TData {
            const index: usize = @intFromEnum(handle);
            std.debug.assert(index < size);

            return &self.data[index];
        }

        pub fn setValue(self: *Self, handle: THandle, data: TData) void {
            const index: usize = @intFromEnum(handle);
            std.debug.assert(index < size);

            self.data[index] = data;
        }
    };
}

pub const RawAllocator = struct {
    const Header = struct {
        const HeaderAlignment = 16; // shold be fine with x86_64 and arm64
        const AlignedSize = (@sizeOf(Header) + HeaderAlignment - 1 / HeaderAlignment) * HeaderAlignment;

        size: usize,
        alignment: u32,
    };

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) RawAllocator {
        return .{
            .allocator = allocator,
        };
    }

    pub fn allocate(self: RawAllocator, size: usize, alignment: u32) ?[*]u8 {
        if (size == 0) return null;

        const ptr = self.allocator.rawAlloc(
            Header.AlignedSize + size,
            .fromByteUnits(alignment),
            @returnAddress(),
        );
        if (ptr == null) return null;

        const header_ptr: *Header = @ptrCast(@alignCast(ptr));
        header_ptr.* = .{
            .size = size,
            .alignment = alignment,
        };
        return ptr.? + Header.AlignedSize;
    }

    pub fn free(self: RawAllocator, ptr: ?[*]u8) void {
        if (ptr == null) return;

        const original_ptr = ptr.? - Header.AlignedSize;
        const header_ptr: *Header = @ptrCast(@alignCast(original_ptr));
        const size = header_ptr.*.size;
        const alignment = header_ptr.*.alignment;

        self.allocator.rawFree(
            original_ptr[0 .. size + Header.AlignedSize],
            .fromByteUnits(alignment),
            @returnAddress(),
        );
    }

    pub fn reallocate(
        self: RawAllocator,
        ptr: ?[*]u8,
        new_size: usize,
        alignment: u32,
    ) ?[*]u8 {
        if (ptr == null) {
            return self.allocate(new_size, alignment);
        }

        const header_ptr: *Header = @ptrCast(@alignCast(ptr.? - Header.AlignedSize));
        const old_size = header_ptr.*.size;
        const old_alignment = header_ptr.*.alignment;

        if (old_size == new_size) return ptr;

        if (new_size == 0) {
            self.free(ptr);
            return null;
        }

        if (old_alignment != alignment) {
            std.log.err(
                "RawAllocator: reallocate: alignment mismatch: {} != {}",
                .{ old_alignment, alignment },
            );
            return null;
        }

        const original_ptr = ptr.? - Header.AlignedSize;
        if (self.allocator.rawRemap(
            original_ptr[0 .. old_size + Header.AlignedSize],
            .fromByteUnits(alignment),
            new_size + Header.AlignedSize,
            @returnAddress(),
        )) |p| {
            const new_header_ptr: *Header = @ptrCast(@alignCast(p));
            new_header_ptr.* = .{
                .size = new_size,
                .alignment = alignment,
            };
            return p + Header.AlignedSize;
        }

        const new_ptr = self.allocate(new_size, alignment);
        if (new_ptr == null) return null;

        const copy_size = @min(new_size, old_size);
        const dest_ptr: [*c]u8 = @ptrCast(@alignCast(new_ptr));
        @memcpy(dest_ptr[0..copy_size], ptr.?[0..copy_size]);

        self.free(ptr);
        return new_ptr;
    }
};

pub const StatisticsAllocator = struct {
    child_allocator: std.mem.Allocator,
    alloc_count: usize,
    alloc_size: usize,

    pub fn init(child_allocator: std.mem.Allocator) StatisticsAllocator {
        return .{
            .child_allocator = child_allocator,
            .alloc_count = 0,
            .alloc_size = 0,
        };
    }

    pub fn allocator(self: *StatisticsAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *StatisticsAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child_allocator.vtable.alloc(
            self.child_allocator.ptr,
            len,
            alignment,
            ret_addr,
        );

        //std.log.debug("Allocating {} bytes at {*}", .{ len, ptr.? });

        _ = @atomicRmw(usize, &self.alloc_count, .Add, 1, .acq_rel);
        _ = @atomicRmw(usize, &self.alloc_size, .Add, len, .acq_rel);

        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *StatisticsAllocator = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.vtable.resize(
            self.child_allocator.ptr,
            memory,
            alignment,
            new_len,
            ret_addr,
        );

        //std.log.debug("Resizing {} bytes at {*}", .{ new_len, memory.ptr });

        if (result) {
            _ = @atomicRmw(usize, &self.alloc_size, .Sub, memory.len, .acq_rel);
            _ = @atomicRmw(usize, &self.alloc_size, .Add, new_len, .acq_rel);
        }

        return result;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *StatisticsAllocator = @ptrCast(@alignCast(ctx));
        const result = self.child_allocator.vtable.remap(
            self.child_allocator.ptr,
            memory,
            alignment,
            new_len,
            ret_addr,
        );

        //std.log.debug("Remapping {} bytes at {*}", .{ new_len, memory.ptr });

        if (result != null) {
            _ = @atomicRmw(usize, &self.alloc_size, .Sub, memory.len, .acq_rel);
            _ = @atomicRmw(usize, &self.alloc_size, .Add, new_len, .acq_rel);
        }

        return result;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *StatisticsAllocator = @ptrCast(@alignCast(ctx));
        self.child_allocator.vtable.free(
            self.child_allocator.ptr,
            memory,
            alignment,
            ret_addr,
        );

        //std.log.debug("Freeing {} bytes at {*}", .{ memory.len, memory.ptr });

        _ = @atomicRmw(usize, &self.alloc_count, .Sub, 1, .acq_rel);
        _ = @atomicRmw(usize, &self.alloc_size, .Sub, memory.len, .acq_rel);
    }
};

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
