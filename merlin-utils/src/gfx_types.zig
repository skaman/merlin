const std = @import("std");

// *********************************************************************************************
// Constants
// *********************************************************************************************

pub const ShaderMagic = @as(u32, @bitCast([_]u8{ 'M', 'S', 'H', 'A' }));
pub const ShaderVersion: u8 = 1;

pub const Colors = struct {
    pub const Black = [4]f32{ 0.0, 0.0, 0.0, 1.0 };
    pub const White = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    pub const Red = [4]f32{ 1.0, 0.0, 0.0, 1.0 };
    pub const Green = [4]f32{ 0.0, 1.0, 0.0, 1.0 };
    pub const Blue = [4]f32{ 0.0, 0.0, 1.0, 1.0 };
    pub const Yellow = [4]f32{ 1.0, 1.0, 0.0, 1.0 };
    pub const Orange = [4]f32{ 1.0, 0.65, 0.0, 1.0 };
    pub const Purple = [4]f32{ 0.5, 0.0, 0.5, 1.0 };
    pub const Cyan = [4]f32{ 0.0, 1.0, 1.0, 1.0 };
    pub const Magenta = [4]f32{ 1.0, 0.0, 1.0, 1.0 };
    pub const Gray = [4]f32{ 0.5, 0.5, 0.5, 1.0 };
    pub const LightGray = [4]f32{ 0.75, 0.75, 0.75, 1.0 };
    pub const Navy = [4]f32{ 0.0, 0.0, 0.5, 1.0 };
    pub const DarkGreen = [4]f32{ 0.0, 0.5, 0.0, 1.0 };
    pub const Olive = [4]f32{ 0.5, 0.5, 0.0, 1.0 };
    pub const Maroon = [4]f32{ 0.5, 0.0, 0.0, 1.0 };
    pub const Teal = [4]f32{ 0.0, 0.5, 0.5, 1.0 };
    pub const Pink = [4]f32{ 1.0, 0.75, 0.8, 1.0 };
    pub const Gold = [4]f32{ 1.0, 0.84, 0.0, 1.0 };
    pub const SkyBlue = [4]f32{ 0.68, 0.85, 0.9, 1.0 };
    pub const Honeydew = [4]f32{ 0.94, 1.0, 0.94, 1.0 };
    pub const Moccasin = [4]f32{ 1.0, 0.94, 0.86, 1.0 };
    pub const Burlywood = [4]f32{ 0.87, 0.72, 0.53, 1.0 };
    pub const PaleVioletRed = [4]f32{ 0.86, 0.44, 0.58, 1.0 };
    pub const YellowGreen = [4]f32{ 0.60, 0.80, 0.20, 1.0 };
    pub const HotPink = [4]f32{ 1.0, 0.08, 0.58, 1.0 };
    pub const SpringGreen = [4]f32{ 0.0, 1.0, 0.5, 1.0 };
    pub const Lavender = [4]f32{ 0.90, 0.90, 0.98, 1.0 };
    pub const Violet = [4]f32{ 0.93, 0.51, 0.93, 1.0 };
    pub const Turquoise = [4]f32{ 0.25, 0.88, 0.82, 1.0 };
    pub const Indigo = [4]f32{ 0.29, 0.0, 0.51, 1.0 };
    pub const Coral = [4]f32{ 1.0, 0.5, 0.31, 1.0 };
    pub const Salmon = [4]f32{ 0.98, 0.5, 0.45, 1.0 };
    pub const Chocolate = [4]f32{ 0.82, 0.41, 0.12, 1.0 };
    pub const Tan = [4]f32{ 0.82, 0.71, 0.55, 1.0 };
    pub const Beige = [4]f32{ 0.96, 0.96, 0.86, 1.0 };
    pub const Aquamarine = [4]f32{ 0.5, 1.0, 0.83, 1.0 };
    pub const SlateBlue = [4]f32{ 0.42, 0.35, 0.80, 1.0 };
    pub const SlateGray = [4]f32{ 0.44, 0.50, 0.56, 1.0 };
    pub const MintCream = [4]f32{ 0.96, 1.0, 0.98, 1.0 };
    pub const PeachPuff = [4]f32{ 1.0, 0.85, 0.73, 1.0 };
    pub const LightSalmon = [4]f32{ 1.0, 0.63, 0.48, 1.0 };
    pub const LightCoral = [4]f32{ 0.94, 0.5, 0.5, 1.0 };
    pub const Khaki = [4]f32{ 0.94, 0.90, 0.55, 1.0 };
    pub const Plum = [4]f32{ 0.87, 0.63, 0.87, 1.0 };
    pub const Orchid = [4]f32{ 0.85, 0.44, 0.84, 1.0 };
    pub const MediumPurple = [4]f32{ 0.58, 0.44, 0.86, 1.0 };
    pub const MediumOrchid = [4]f32{ 0.73, 0.33, 0.83, 1.0 };
    pub const MediumSeaGreen = [4]f32{ 0.24, 0.70, 0.44, 1.0 };
    pub const MediumSlateBlue = [4]f32{ 0.48, 0.41, 0.93, 1.0 };
    pub const MediumTurquoise = [4]f32{ 0.28, 0.82, 0.80, 1.0 };
    pub const LightSeaGreen = [4]f32{ 0.13, 0.70, 0.67, 1.0 };
    pub const DarkTurquoise = [4]f32{ 0.0, 0.81, 0.82, 1.0 };
    pub const LightSteelBlue = [4]f32{ 0.69, 0.77, 0.87, 1.0 };
    pub const LightBlue = [4]f32{ 0.68, 0.85, 0.90, 1.0 };
    pub const PowderBlue = [4]f32{ 0.69, 0.88, 0.90, 1.0 };
    pub const Firebrick = [4]f32{ 0.70, 0.13, 0.13, 1.0 };
    pub const DarkOrange = [4]f32{ 1.0, 0.55, 0.0, 1.0 };
    pub const DarkViolet = [4]f32{ 0.58, 0.0, 0.83, 1.0 };
    pub const DarkSlateBlue = [4]f32{ 0.28, 0.24, 0.55, 1.0 };
    pub const DarkOliveGreen = [4]f32{ 0.33, 0.42, 0.18, 1.0 };
    pub const DarkKhaki = [4]f32{ 0.74, 0.72, 0.42, 1.0 };
    pub const RoyalBlue = [4]f32{ 0.25, 0.41, 0.88, 1.0 };
    pub const Linen = [4]f32{ 0.98, 0.94, 0.90, 1.0 };
};

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

pub const PushConstant = struct {
    name: []const u8,
    offset: u32,
    size: u32,
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
    push_constants: []const PushConstant,
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
