const std = @import("std");

pub const Attribute = enum(u8) {
    position,
    normal,
    tangent,
    bitangent,
    color_0,
    color_1,
    color_2,
    color_3,
    indices,
    weight,
    tex_coord_0,
    tex_coord_1,
    tex_coord_2,
    tex_coord_3,
    tex_coord_4,
    tex_coord_5,
    tex_coord_6,
    tex_coord_7,
};

pub const AttributeType = enum(u8) {
    uint_8,
    uint_10,
    int_16,
    half,
    float,

    const SizeTable = [_][4]u8{
        [_]u8{ 1, 2, 4, 4 }, // uint_8
        [_]u8{ 4, 4, 4, 4 }, // uint_10
        [_]u8{ 2, 4, 8, 8 }, // int_16
        [_]u8{ 2, 4, 8, 8 }, // half
        [_]u8{ 4, 8, 12, 16 }, // float
    };

    pub fn getSize(self: AttributeType, num: u3) u8 {
        return SizeTable[@intFromEnum(self)][num - 1];
    }
};

pub const AttributeData = packed struct {
    normalized: bool,
    type: AttributeType,
    num: u3,
    as_int: bool,
};

pub const VertexLayout = struct {
    const Self = @This();

    stride: u16,
    offsets: [@typeInfo(Attribute).@"enum".fields.len]u16,
    attributes: [@typeInfo(Attribute).@"enum".fields.len]AttributeData,

    pub fn init() VertexLayout {
        var offsets: [@typeInfo(Attribute).@"enum".fields.len]u16 = undefined;
        @memset(&offsets, 0);

        var attributes: [@typeInfo(Attribute).@"enum".fields.len]AttributeData = undefined;
        @memset(&attributes, .{ .normalized = false, .type = .uint_8, .num = 0, .as_int = false });

        return .{
            .stride = 0,
            .offsets = offsets,
            .attributes = attributes,
        };
    }

    pub fn add(self: *Self, attribute: Attribute, num: u3, type_: AttributeType, normalized: bool, as_int: bool) void {
        const index = @intFromEnum(attribute);
        const size = type_.getSize(num);

        self.attributes[index] = .{
            .normalized = normalized,
            .type = type_,
            .num = num,
            .as_int = as_int,
        };
        self.offsets[index] = self.stride;
        self.stride += size;
    }

    pub fn skip(self: *Self, num: u8) void {
        self.stride += num;
    }
};

pub const ShaderType = enum(u8) {
    vertex,
    fragment,
};

pub const ShaderData = struct {
    const Self = @This();

    const Magic = [_]u8{ 'Z', '3', 'S', 'H' };
    const Version: u8 = 1;

    allocator: std.mem.Allocator,
    shader_type: ShaderType,
    data: []align(@alignOf(u32)) u8,
    input_attributes: []?Attribute,

    pub fn init(
        allocator: std.mem.Allocator,
        shader_type: ShaderType,
        data: []const u8,
        input_attributes: []?Attribute,
    ) !Self {
        const aligned_data = try allocator.alignedAlloc(u8, @alignOf(u32), data.len);
        errdefer allocator.free(aligned_data);

        @memcpy(aligned_data, data);

        return .{
            .allocator = allocator,
            .shader_type = shader_type,
            .data = aligned_data,
            .input_attributes = try allocator.dupe(?Attribute, input_attributes),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
        self.allocator.free(self.input_attributes);
    }

    pub fn write(self: *Self, writer: anytype) !void {
        try writer.writeAll(&Magic);
        try writer.writeInt(u8, Version, .little);
        try writer.writeInt(u8, @intFromEnum(self.shader_type), .little);
        try writer.writeInt(u32, @intCast(self.data.len), .little);
        try writer.writeAll(self.data);
        try writer.writeInt(u8, @intCast(self.input_attributes.len), .little);
        for (self.input_attributes) |attribute| {
            try writer.writeInt(u8, @intFromBool(attribute != null), .little);
            if (attribute == null) {
                continue;
            }
            try writer.writeInt(u8, @intFromEnum(attribute.?), .little);
        }
    }

    pub fn read(allocator: std.mem.Allocator, reader: anytype) !Self {
        var magic: [4]u8 = undefined;
        _ = try reader.readAll(&magic);
        if (!std.mem.eql(u8, &Magic, &magic)) {
            return error.InvalidMagic;
        }

        const version = try reader.readInt(u8, .little);
        if (version != Version) {
            return error.InvalidVersion;
        }

        var self = Self{
            .allocator = allocator,
            .shader_type = undefined,
            .data = undefined,
            .input_attributes = undefined,
        };

        self.shader_type = try reader.readEnum(ShaderType, .little);

        const data_len = try reader.readInt(u32, .little);
        self.data = try allocator.alignedAlloc(u8, @alignOf(u32), @intCast(data_len));
        errdefer allocator.free(self.data);

        const data_read = try reader.readAll(self.data);
        if (data_read != data_len) {
            return error.InvalidData;
        }

        const input_attributes_len = try reader.readInt(u8, .little);
        self.input_attributes = try allocator.alloc(?Attribute, @intCast(input_attributes_len));
        errdefer allocator.free(self.input_attributes);

        for (0..input_attributes_len) |i| {
            const exists = try reader.readInt(u8, .little);
            if (exists == 0) {
                self.input_attributes[i] = null;
                continue;
            }

            self.input_attributes[i] = try reader.readEnum(Attribute, .little);
        }

        return self;
    }
};
