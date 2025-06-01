const std = @import("std");

const image = @import("merlin_image");

const c = @import("c.zig").c;

// TODO: remove if and when it's fixed in the KTX library
// For some reason this method is missing from the header file
extern fn ktxTexture2_SetImageFromMemory(
    This: [*c]c.ktxTexture2,
    level: c.ktx_uint32_t,
    layer: c.ktx_uint32_t,
    faceSlice: c.ktx_uint32_t,
    src: [*c]c.ktx_uint8_t,
    srcSize: c.ktx_size_t,
) c.ktx_error_code_e;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn checkKtxError(comptime message: []const u8, result: c.KTX_error_code) !void {
    if (result != c.VK_SUCCESS) {
        std.log.err("{s}: {s}", .{ message, c.ktxErrorString(result) });
        return error.KTXError;
    }
}

fn getGlInternalFormat(channels: usize, channel_size: image.ChannelSize, srgb: bool) !c.GLenum {
    if (channels == 1) {
        switch (channel_size) {
            .u8 => return if (srgb) c.GL_SR8_EXT else c.GL_R8,
            .u16 => return c.GL_R16,
            .f32 => return c.GL_R32F,
        }
    } else if (channels == 2) {
        switch (channel_size) {
            // TODO: 0x8FBE should be GL_SRG8_EXT, but it's not defined
            // in the header file on windows.
            .u8 => return if (srgb) 0x8FBE else c.GL_RG8,
            .u16 => return c.GL_RG16,
            .f32 => return c.GL_RG32F,
        }
    } else if (channels == 3) {
        switch (channel_size) {
            .u8 => return if (srgb) c.GL_SRGB8 else c.GL_RGB8,
            .u16 => return c.GL_RGB16,
            .f32 => return c.GL_RGB32F,
        }
    } else if (channels == 4) {
        switch (channel_size) {
            .u8 => return if (srgb) c.GL_SRGB8_ALPHA8 else c.GL_RGBA8,
            .u16 => return c.GL_RGBA16,
            .f32 => return c.GL_RGBA32F,
        }
    }

    std.log.err("Unsupported number of channels: {d}\n", .{channels});
    return error.ImageError;
}

fn getVulkanFormat(channels: usize, channel_size: image.ChannelSize, srgb: bool) !c.VkFormat {
    if (channels == 1) {
        switch (channel_size) {
            .u8 => return if (srgb) c.VK_FORMAT_R8_SRGB else c.VK_FORMAT_R8_UNORM,
            .u16 => return c.VK_FORMAT_R16_UNORM,
            .f32 => return c.VK_FORMAT_R32_SFLOAT,
        }
    } else if (channels == 2) {
        switch (channel_size) {
            .u8 => return if (srgb) c.VK_FORMAT_R8G8_SRGB else c.VK_FORMAT_R8G8_UNORM,
            .u16 => return c.VK_FORMAT_R16G16_UNORM,
            .f32 => return c.VK_FORMAT_R32G32_SFLOAT,
        }
    } else if (channels == 3) {
        switch (channel_size) {
            .u8 => return if (srgb) c.VK_FORMAT_R8G8B8_SRGB else c.VK_FORMAT_R8G8B8_UNORM,
            .u16 => return c.VK_FORMAT_R16G16B16_UNORM,
            .f32 => return c.VK_FORMAT_R32G32B32_SFLOAT,
        }
    } else if (channels == 4) {
        switch (channel_size) {
            .u8 => return if (srgb) c.VK_FORMAT_R8G8B8A8_SRGB else c.VK_FORMAT_R8G8B8A8_UNORM,
            .u16 => return c.VK_FORMAT_R16G16B16A16_UNORM,
            .f32 => return c.VK_FORMAT_R32G32B32A32_SFLOAT,
        }
    }

    std.log.err("Unsupported number of channels: {d}\n", .{channels});
    return error.ImageError;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub const Texture = struct {
    allocator: std.mem.Allocator,
    texture: *c.ktxTexture2 = undefined,

    pub const CreateOptions = struct {
        num_channels: usize,
        channel_size: image.ChannelSize,
        srgb: bool,
        base_width: u32,
        base_height: u32,
        base_depth: u32 = 1,
        num_dimensions: u32 = 2,
        num_levels: u32 = 1,
        num_layers: u32 = 1,
        num_faces: u32 = 1,
        is_array: bool = false,
        generate_mipmaps: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, options: CreateOptions) !Texture {
        var create_info = std.mem.zeroInit(
            c.ktxTextureCreateInfo,
            .{
                .glInternalformat = try getGlInternalFormat(
                    options.num_channels,
                    options.channel_size,
                    options.srgb,
                ),
                .vkFormat = try getVulkanFormat(
                    options.num_channels,
                    options.channel_size,
                    options.srgb,
                ),
                .baseWidth = options.base_width,
                .baseHeight = options.base_height,
                .baseDepth = options.base_depth,
                .numDimensions = options.num_dimensions,
                .numLevels = options.num_levels,
                .numLayers = options.num_layers,
                .numFaces = options.num_faces,
                .isArray = options.is_array,
                .generateMipmaps = options.generate_mipmaps,
            },
        );

        var ktx_texture: *c.ktxTexture2 = undefined;
        try checkKtxError(
            "Failed to create KTX texture",
            c.ktxTexture2_Create(
                &create_info,
                c.KTX_TEXTURE_CREATE_ALLOC_STORAGE,
                @ptrCast(&ktx_texture),
            ),
        );

        return .{
            .allocator = allocator,
            .texture = ktx_texture,
        };
    }

    pub fn deinit(self: *const Texture) void {
        c.ktxTexture2_Destroy(self.texture);
    }

    pub fn setImage(
        self: *const Texture,
        data: []u8,
        level: u32,
        layer: u32,
        face_slice: u32,
    ) !void {
        try checkKtxError(
            "Failed to set image data",
            ktxTexture2_SetImageFromMemory(
                self.texture,
                level,
                layer,
                face_slice,
                data.ptr,
                @intCast(data.len),
            ),
        );
    }

    pub fn compressBasis(
        self: *const Texture,
        normalmap: bool,
        level: u32,
        quality: u32,
        threads: u32,
    ) !void {
        var basis_params = std.mem.zeroInit(
            c.ktxBasisParams,
            .{
                .structSize = @sizeOf(c.ktxBasisParams),
                .compressionLevel = level,
                .qualityLevel = quality,
                .threadCount = threads,
                .normalMap = normalmap,
            },
        );

        try checkKtxError(
            "Failed to transcode KTX texture",
            c.ktxTexture2_CompressBasisEx(self.texture, &basis_params),
        );
    }

    pub fn save(self: *const Texture, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        try checkKtxError(
            "Failed to write KTX texture",
            c.ktxTexture2_WriteToNamedFile(self.texture, path_z.ptr),
        );
    }
};
