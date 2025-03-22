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

fn checkKtxError(comptime message: []const u8, result: c.KTX_error_code) !void {
    if (result != c.VK_SUCCESS) {
        std.log.err("{s}: {s}", .{ message, c.ktxErrorString(result) });
        return error.KTXError;
    }
}

pub const Texture = struct {
    allocator: std.mem.Allocator,
    image: image.Image,
    texture: *c.ktxTexture2,

    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        srgb: bool,
    ) !Texture {
        const source = try image.Image.init(path);
        var create_info = std.mem.zeroInit(
            c.ktxTextureCreateInfo,
            .{
                .numFaces = 1,
                .numLayers = 1,
                .isArray = false,
            },
        );

        if (source.channels == 1) {
            switch (source.channel_size) {
                .u8 => {
                    create_info.glInternalformat = if (srgb) c.GL_SR8_EXT else c.GL_R8;
                    create_info.vkFormat = if (srgb) c.VK_FORMAT_R8_SRGB else c.VK_FORMAT_R8_UNORM;
                },
                .u16 => {
                    create_info.glInternalformat = c.GL_R16;
                    create_info.vkFormat = c.VK_FORMAT_R16_UNORM;
                },
                .f32 => {
                    create_info.glInternalformat = c.GL_R32F;
                    create_info.vkFormat = c.VK_FORMAT_R32_SFLOAT;
                },
            }
        } else if (source.channels == 2) {
            switch (source.channel_size) {
                .u8 => {
                    create_info.glInternalformat = if (srgb) c.GL_SRG8_EXT else c.GL_RG8;
                    create_info.vkFormat = if (srgb) c.VK_FORMAT_R8G8_SRGB else c.VK_FORMAT_R8G8_UNORM;
                },
                .u16 => {
                    create_info.glInternalformat = c.GL_RG16;
                    create_info.vkFormat = c.VK_FORMAT_R16G16_UNORM;
                },
                .f32 => {
                    create_info.glInternalformat = c.GL_RG32F;
                    create_info.vkFormat = c.VK_FORMAT_R32G32_SFLOAT;
                },
            }
        } else if (source.channels == 3) {
            switch (source.channel_size) {
                .u8 => {
                    create_info.glInternalformat = if (srgb) c.GL_SRGB8 else c.GL_RGB8;
                    create_info.vkFormat = if (srgb) c.VK_FORMAT_R8G8B8_SRGB else c.VK_FORMAT_R8G8B8_UNORM;
                },
                .u16 => {
                    create_info.glInternalformat = c.GL_RGB16;
                    create_info.vkFormat = c.VK_FORMAT_R16G16B16_UNORM;
                },
                .f32 => {
                    create_info.glInternalformat = c.GL_RGB32F;
                    create_info.vkFormat = c.VK_FORMAT_R32G32B32_SFLOAT;
                },
            }
        } else if (source.channels == 4) {
            switch (source.channel_size) {
                .u8 => {
                    create_info.glInternalformat = if (srgb) c.GL_SRGB8_ALPHA8 else c.GL_RGBA8;
                    create_info.vkFormat = if (srgb) c.VK_FORMAT_R8G8B8A8_SRGB else c.VK_FORMAT_R8G8B8A8_UNORM;
                },
                .u16 => {
                    create_info.glInternalformat = c.GL_RGBA16;
                    create_info.vkFormat = c.VK_FORMAT_R16G16B16A16_UNORM;
                },
                .f32 => {
                    create_info.glInternalformat = c.GL_RGBA32F;
                    create_info.vkFormat = c.VK_FORMAT_R32G32B32A32_SFLOAT;
                },
            }
        } else {
            std.log.err("Unsupported number of channels: {d}\n", .{source.channels});
            return error.ImageError;
        }

        create_info.baseWidth = @intCast(source.width);
        create_info.baseHeight = @intCast(source.height);
        create_info.baseDepth = 1;
        create_info.numDimensions = 2;

        create_info.generateMipmaps = false;
        //create_info.numLevels = 1;
        const max_dim = @max(source.width, source.height);
        create_info.numLevels = @intCast(std.math.log2(max_dim) + 1);

        var ktx_texture: *c.ktxTexture2 = undefined;
        try checkKtxError(
            "Failed to create KTX texture",
            c.ktxTexture2_Create(
                &create_info,
                c.KTX_TEXTURE_CREATE_ALLOC_STORAGE,
                @ptrCast(&ktx_texture),
            ),
        );

        try checkKtxError(
            "Failed to load image data",
            ktxTexture2_SetImageFromMemory(
                ktx_texture,
                0,
                0,
                0,
                source.data.ptr,
                source.data.len,
            ),
        );

        return .{
            .allocator = allocator,
            .image = source,
            .texture = ktx_texture,
        };
    }

    pub fn deinit(self: *const Texture) void {
        self.image.deinit();
        c.ktxTexture2_Destroy(self.texture);
    }

    fn save(self: *const Texture, path: []const u8) !void {
        const path_z = self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        try checkKtxError(
            "Failed to write KTX texture",
            c.ktxTexture2_WriteToNamedFile(self.texture, path_z.ptr),
        );
    }

    pub fn compress(
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

    pub fn genMipmaps(
        self: *const Texture,
        layer: u32,
        face_slice: u32,
        edge: image.ResizeEdge,
        filter: image.ResizeFilter,
    ) !void {
        for (1..self.texture.numLevels) |level| {
            const output_width = @as(u32, @intCast(@max(1, self.image.width >> @intCast(level))));
            const output_height = @as(u32, @intCast(@max(1, self.image.height >> @intCast(level))));

            const resized_image = try self.image.resize(output_width, output_height, edge, filter);
            defer resized_image.deinit();

            try checkKtxError(
                "Failed to set image data",
                ktxTexture2_SetImageFromMemory(
                    self.texture,
                    @intCast(level),
                    layer,
                    face_slice,
                    resized_image.data.ptr,
                    resized_image.data.len,
                ),
            );
        }
    }
};
