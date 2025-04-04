const std = @import("std");

// *********************************************************************************************
// Constants
// *********************************************************************************************

pub const ShaderMagic = @as(u32, @bitCast([_]u8{ 'M', 'S', 'H', 'A' }));
pub const ShaderVersion: u8 = 1;

//pub const VertexBufferMagic = @as(u32, @bitCast([_]u8{ 'M', 'V', 'B', 'D' }));
//pub const VertexBufferVersion: u8 = 1;
//
//pub const IndexBufferMagic = @as(u32, @bitCast([_]u8{ 'M', 'I', 'B', 'D' }));
//pub const IndexBufferVersion: u8 = 1;

// *********************************************************************************************
// Structs and Enums
// *********************************************************************************************

pub const AlphaMode = enum(u8) {
    opaque_,
    mask,
    blend,

    pub fn name(self: AlphaMode) []const u8 {
        return switch (self) {
            .opaque_ => "opaque",
            .mask => "mask",
            .blend => "blend",
        };
    }
};

pub const IndexType = enum(u8) {
    u8,
    u16,
    u32,

    const SizeTable = [_]u8{
        1, // u8
        2, // u16
        4, // u32
    };

    pub inline fn size(self: IndexType) u8 {
        return SizeTable[@intFromEnum(self)];
    }

    pub fn name(self: IndexType) []const u8 {
        return switch (self) {
            .u8 => "u8",
            .u16 => "u16",
            .u32 => "u32",
        };
    }
};

pub const DescriptorBindType = enum(u8) {
    uniform_buffer,
    combined_sampler,

    pub fn name(self: DescriptorBindType) []const u8 {
        return switch (self) {
            .uniform_buffer => "uniform_buffer",
            .combined_sampler => "combined_sampler",
        };
    }
};

pub const DescriptorBinding = struct {
    type: DescriptorBindType,
    binding: u32,
    size: u32,
    name: []const u8,
};

pub const DescriptorSet = struct {
    set: u32,
    bindings: []const DescriptorBinding,
};

pub const ShaderType = enum(u8) {
    vertex,
    fragment,
};

pub const ShaderInputAttribute = struct {
    attribute: VertexAttributeType,
    location: u8,
};

pub const ShaderData = struct {
    type: ShaderType,
    data: []align(@alignOf(u32)) const u8,
    input_attributes: []const ShaderInputAttribute,
    descriptor_sets: []const DescriptorSet,
};

pub const VertexAttributeType = enum(u8) {
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

    pub fn name(self: VertexAttributeType) []const u8 {
        return switch (self) {
            .position => "position",
            .normal => "normal",
            .tangent => "tangent",
            .bitangent => "bitangent",
            .color_0 => "color_0",
            .color_1 => "color_1",
            .color_2 => "color_2",
            .color_3 => "color_3",
            .indices => "indices",
            .weight => "weight",
            .tex_coord_0 => "tex_coord_0",
            .tex_coord_1 => "tex_coord_1",
            .tex_coord_2 => "tex_coord_2",
            .tex_coord_3 => "tex_coord_3",
            .tex_coord_4 => "tex_coord_4",
            .tex_coord_5 => "tex_coord_5",
            .tex_coord_6 => "tex_coord_6",
            .tex_coord_7 => "tex_coord_7",
        };
    }
};

pub const VertexComponentType = enum(u8) {
    i8,
    u8,
    i16,
    u16,
    u32,
    f32,

    const SizeTable = [_][4]u8{
        [_]u8{ 1, 2, 4, 4 }, // i8
        [_]u8{ 1, 2, 4, 4 }, // u8
        [_]u8{ 2, 4, 8, 8 }, // i16
        [_]u8{ 2, 4, 8, 8 }, // u16
        [_]u8{ 4, 8, 12, 16 }, // u32
        [_]u8{ 4, 8, 12, 16 }, // f32
    };

    pub inline fn size(self: VertexComponentType, num: u8) u8 {
        std.debug.assert(num <= SizeTable[0].len);

        return SizeTable[@intFromEnum(self)][num - 1];
    }

    pub fn name(self: VertexComponentType) []const u8 {
        return switch (self) {
            .i8 => "i8",
            .u8 => "u8",
            .i16 => "i16",
            .u16 => "u16",
            .u32 => "u32",
            .f32 => "f32",
        };
    }
};

pub const VertexAttribute = packed struct {
    normalized: bool,
    type: VertexComponentType,
    num: u8,
};

pub const VertexLayout = struct {
    stride: u16,
    offsets: [@typeInfo(VertexAttributeType).@"enum".fields.len]u16,
    attributes: [@typeInfo(VertexAttributeType).@"enum".fields.len]VertexAttribute,

    pub fn init() VertexLayout {
        var offsets: [@typeInfo(VertexAttributeType).@"enum".fields.len]u16 = undefined;
        @memset(&offsets, 0);

        var attributes: [@typeInfo(VertexAttributeType).@"enum".fields.len]VertexAttribute = undefined;
        @memset(&attributes, .{ .normalized = false, .type = .u8, .num = 0 });

        return .{
            .stride = 0,
            .offsets = offsets,
            .attributes = attributes,
        };
    }

    pub fn add(
        self: *VertexLayout,
        attribute: VertexAttributeType,
        num: u8,
        type_: VertexComponentType,
        normalized: bool,
    ) void {
        const index = @intFromEnum(attribute);
        const size = type_.size(num);

        self.attributes[index] = .{
            .normalized = normalized,
            .type = type_,
            .num = num,
        };
        self.offsets[index] = self.stride;
        self.stride += size;
    }

    pub fn skip(self: *VertexLayout, num: u8) void {
        self.stride += num;
    }
};
