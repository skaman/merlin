const std = @import("std");

const types = @import("gfx_types.zig");
const utils = @import("utils.zig");

// TODO: Need a better memory allocation strategy. Required for future async loading.

// *********************************************************************************************
// ShaderLoader
// *********************************************************************************************

pub const ShaderFileLoader = struct {
    filename: []const u8,

    pub fn read(self: *const ShaderFileLoader, allocator: std.mem.Allocator) !types.ShaderData {
        var file = try std.fs.cwd().openFile(self.filename, .{});
        defer file.close();

        const reader = file.reader();

        try utils.Serializer.checkHeader(reader, types.ShaderMagic, types.ShaderVersion);
        const shader_data = try utils.Serializer.read(
            types.ShaderData,
            allocator,
            reader,
        );
        return shader_data;
    }
};

pub const ShaderMemoryLoader = struct {
    data: types.ShaderData,

    pub fn read(self: *const ShaderMemoryLoader, _: std.mem.Allocator) !types.ShaderData {
        return self.data;
    }
};

pub const ShaderLoader = union(enum) {
    file: ShaderFileLoader,
    memory: ShaderMemoryLoader,

    pub fn read(self: *const ShaderLoader, allocator: std.mem.Allocator) !types.ShaderData {
        switch (self.*) {
            inline else => |*case| return try case.read(allocator),
        }
    }

    pub fn from(ctx: *anyopaque, comptime T: type) ShaderLoader {
        const ref: *T = @ptrCast(@alignCast(ctx));
        switch (T) {
            ShaderFileLoader => return ShaderLoader{ .file = ref.* },
            ShaderMemoryLoader => return ShaderLoader{ .memory = ref.* },
            else => @compileError("Unsupported shader loader type"),
        }
    }
};

// *********************************************************************************************
// TextureLoader
// *********************************************************************************************

pub const TextureFileLoader = struct {
    const MaxBufferSize = 256 * 1024 * 1024; // 256 MB max for a texture. Should be more than enough.

    filename: []const u8,

    pub fn read(self: *const TextureFileLoader, allocator: std.mem.Allocator) ![]const u8 {
        var file = try std.fs.cwd().openFile(self.filename, .{});
        defer file.close();

        const reader = file.reader();

        return try reader.readAllAlloc(
            allocator,
            MaxBufferSize,
        );
    }
};

pub const TextureMemoryLoader = struct {
    data: []const u8,

    pub fn read(self: *const TextureMemoryLoader, _: std.mem.Allocator) ![]const u8 {
        return self.data;
    }
};

pub const TextureLoader = union(enum) {
    file: TextureFileLoader,
    memory: TextureMemoryLoader,

    pub fn read(self: *const TextureLoader, allocator: std.mem.Allocator) ![]const u8 {
        switch (self.*) {
            inline else => |*case| return try case.read(allocator),
        }
    }

    pub fn from(ctx: *anyopaque, comptime T: type) TextureLoader {
        const ref: *T = @ptrCast(@alignCast(ctx));
        switch (T) {
            TextureFileLoader => return TextureLoader{ .file = ref.* },
            TextureMemoryLoader => return TextureLoader{ .memory = ref.* },
            else => @compileError("Unsupported shader loader type"),
        }
    }
};

// *********************************************************************************************
// VertexBufferLoader
// *********************************************************************************************

pub const VertexBufferFileLoader = struct {
    const VertexLayoutSize = 92;

    filename: []const u8,
    file: ?std.fs.File = null,

    pub fn open(self: *VertexBufferFileLoader) !void {
        self.file = try std.fs.cwd().openFile(self.filename, .{});
        try utils.Serializer.checkHeader(
            self.file.?.reader(),
            types.VertexBufferMagic,
            types.VertexBufferVersion,
        );
    }

    pub fn close(self: *VertexBufferFileLoader) void {
        std.debug.assert(self.file != null);
        self.file.?.close();
    }

    pub fn readLayout(
        self: *const VertexBufferFileLoader,
        allocator: std.mem.Allocator,
    ) !types.VertexLayout {
        std.debug.assert(self.file != null);

        try self.file.?.seekTo(utils.Serializer.HeaderSize);

        return try utils.Serializer.read(
            types.VertexLayout,
            allocator,
            self.file.?.reader(),
        );
    }

    pub fn readDataSize(self: *const VertexBufferFileLoader) !usize {
        std.debug.assert(self.file != null);

        const offset = utils.Serializer.HeaderSize + VertexLayoutSize;

        try self.file.?.seekTo(offset);
        return try self.file.?.reader().readInt(usize, utils.Serializer.Endian);
    }

    pub fn readData(
        self: *const VertexBufferFileLoader,
        output_buffer: []u8,
    ) !void {
        std.debug.assert(self.file != null);

        const offset = utils.Serializer.HeaderSize + VertexLayoutSize + @sizeOf(usize);

        try self.file.?.seekTo(offset);
        const readed_size = try self.file.?.reader().readAll(output_buffer);

        std.debug.assert(readed_size == output_buffer.len);
    }
};

pub const VertexBufferMemoryLoader = struct {
    data: []const u8,
    layout: types.VertexLayout,

    pub fn open(_: *VertexBufferMemoryLoader) !void {}
    pub fn close(_: *VertexBufferMemoryLoader) void {}

    pub fn readLayout(
        self: *const VertexBufferMemoryLoader,
        _: std.mem.Allocator,
    ) !types.VertexLayout {
        return self.layout;
    }

    pub fn readDataSize(self: *const VertexBufferMemoryLoader) !usize {
        return self.data.len;
    }

    pub fn readData(
        self: *const VertexBufferMemoryLoader,
        output_buffer: []u8,
    ) !void {
        @memcpy(output_buffer, self.data);
    }
};

pub const VertexBufferLoader = union(enum) {
    file: VertexBufferFileLoader,
    memory: VertexBufferMemoryLoader,

    pub fn open(self: *VertexBufferLoader) !void {
        switch (self.*) {
            inline else => |*case| return try case.open(),
        }
    }

    pub fn close(self: *VertexBufferLoader) void {
        switch (self.*) {
            inline else => |*case| return case.close(),
        }
    }

    pub fn readLayout(
        self: *const VertexBufferLoader,
        allocator: std.mem.Allocator,
    ) !types.VertexLayout {
        switch (self.*) {
            inline else => |*case| return try case.readLayout(allocator),
        }
    }

    pub fn readDataSize(self: *const VertexBufferLoader) !usize {
        switch (self.*) {
            inline else => |*case| return try case.readDataSize(),
        }
    }

    pub fn readData(
        self: *const VertexBufferLoader,
        output_buffer: []u8,
    ) !void {
        switch (self.*) {
            inline else => |*case| return try case.readData(output_buffer),
        }
    }

    pub fn from(ctx: *anyopaque, comptime T: type) VertexBufferLoader {
        const ref: *T = @ptrCast(@alignCast(ctx));
        switch (T) {
            VertexBufferFileLoader => return VertexBufferLoader{ .file = ref.* },
            VertexBufferMemoryLoader => return VertexBufferLoader{ .memory = ref.* },
            else => @compileError("Unsupported vertex buffer loader type"),
        }
    }
};

// *********************************************************************************************
// IndexBufferLoader
// *********************************************************************************************

pub const IndexBufferFileLoader = struct {
    filename: []const u8,
    file: ?std.fs.File = null,

    pub fn open(self: *IndexBufferFileLoader) !void {
        self.file = try std.fs.cwd().openFile(self.filename, .{});
        try utils.Serializer.checkHeader(
            self.file.?.reader(),
            types.IndexBufferMagic,
            types.IndexBufferVersion,
        );
    }

    pub fn close(self: *IndexBufferFileLoader) void {
        std.debug.assert(self.file != null);
        self.file.?.close();
    }

    pub fn readIndexType(
        self: *const IndexBufferFileLoader,
    ) !types.IndexType {
        std.debug.assert(self.file != null);

        try self.file.?.seekTo(utils.Serializer.HeaderSize);

        return try self.file.?.reader().readEnum(types.IndexType, utils.Serializer.Endian);
    }

    pub fn readDataSize(self: *const IndexBufferFileLoader) !usize {
        std.debug.assert(self.file != null);

        const offset = utils.Serializer.HeaderSize + @sizeOf(types.IndexType);

        try self.file.?.seekTo(offset);
        return try self.file.?.reader().readInt(usize, utils.Serializer.Endian);
    }

    pub fn readData(
        self: *const IndexBufferFileLoader,
        output_buffer: []u8,
    ) !void {
        std.debug.assert(self.file != null);

        const offset = utils.Serializer.HeaderSize + @sizeOf(types.IndexType) + @sizeOf(usize);

        try self.file.?.seekTo(offset);
        const readed_size = try self.file.?.reader().readAll(output_buffer);

        std.debug.assert(readed_size == output_buffer.len);
    }
};

pub const IndexBufferMemoryLoader = struct {
    index_type: types.IndexType,
    data: []const u8,

    pub fn open(_: *IndexBufferMemoryLoader) !void {}
    pub fn close(_: *IndexBufferMemoryLoader) void {}

    pub fn readIndexType(
        self: *const IndexBufferMemoryLoader,
    ) !types.IndexType {
        return self.index_type;
    }

    pub fn readDataSize(self: *const IndexBufferMemoryLoader) !usize {
        return self.data.len;
    }

    pub fn readData(
        self: *const IndexBufferMemoryLoader,
        output_buffer: []u8,
    ) !void {
        @memcpy(output_buffer, self.data);
    }
};

pub const IndexBufferLoader = union(enum) {
    file: IndexBufferFileLoader,
    memory: IndexBufferMemoryLoader,

    pub fn open(self: *IndexBufferLoader) !void {
        switch (self.*) {
            inline else => |*case| return try case.open(),
        }
    }

    pub fn close(self: *IndexBufferLoader) void {
        switch (self.*) {
            inline else => |*case| return case.close(),
        }
    }

    pub fn readIndexType(
        self: *const IndexBufferLoader,
    ) !types.IndexType {
        switch (self.*) {
            inline else => |*case| return try case.readIndexType(),
        }
    }

    pub fn readDataSize(self: *const IndexBufferLoader) !usize {
        switch (self.*) {
            inline else => |*case| return try case.readDataSize(),
        }
    }

    pub fn readData(
        self: *const IndexBufferLoader,
        output_buffer: []u8,
    ) !void {
        switch (self.*) {
            inline else => |*case| return try case.readData(output_buffer),
        }
    }

    pub fn from(ctx: *anyopaque, comptime T: type) IndexBufferLoader {
        const ref: *T = @ptrCast(@alignCast(ctx));
        switch (T) {
            IndexBufferFileLoader => return IndexBufferLoader{ .file = ref.* },
            IndexBufferMemoryLoader => return IndexBufferLoader{ .memory = ref.* },
            else => @compileError("Unsupported index buffer loader type"),
        }
    }
};
