const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// The part related to KTX texture loading come directly from the KTX library (vkloader.c)

// TODO: remove if and when it's fixed in the KTX library
// For some reason this method is missing from the header file
extern fn ktxTexture2_IterateLevels(
    This: [*c]c.ktxTexture2,
    iter_cb: c.PFNKTXITERCB,
    userdata: *anyopaque,
) c.KTX_error_code;

extern fn ktxTexture2_GetDataSizeUncompressed(
    This: [*c]c.ktxTexture2,
) c.ktx_size_t;

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Texture = struct {
    image: vk.images.Image,
    image_layout: c.VkImageLayout,
    image_view: c.VkImageView,
    sampler: c.VkSampler,
    debug_name: ?[]const u8,
};

const UserCallbackDataOptimal = struct {
    regions: []c.VkBufferImageCopy,
    region_index: u32,
    offset: c.VkDeviceSize,
    num_faces: c.ktx_uint32_t,
    num_layers: c.ktx_uint32_t,
};

const UserCallbackDataLinear = struct {
    dest_image: c.VkImage,
    dest: [*c]u8,
};

const TextureParams = struct {
    tiling: c.VkImageTiling,
    format: c.VkFormat,
    width: u32,
    height: u32,
    depth: u32,
    num_image_levels: u32,
    num_image_layers: u32,
    usage_flags: c.VkImageUsageFlags,
    blit_filter: c.VkFilter,
    final_layout: c.VkImageLayout,
    view_type: c.VkImageViewType,
    create_flags: c.VkImageCreateFlags,
};

const PrepareTextureParams = struct {
    format: c.VkFormat,
    width: u32,
    height: u32,
    depth: u32,
    usage_flags: c.VkImageUsageFlags = c.VK_IMAGE_USAGE_SAMPLED_BIT,
    tiling: c.VkImageTiling = c.VK_IMAGE_TILING_OPTIMAL,
    final_layout: c.VkImageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    num_image_layers: u32 = 1,
    num_image_levels: u32 = 1,
    num_dimensions: u32 = 2,
    is_cubemap: bool = false,
    is_array: bool = false,
    generate_mipmaps: bool = false,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _textures_to_destroy: std.ArrayList(*Texture) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn checkKtxError(comptime message: []const u8, result: c.KTX_error_code) !void {
    if (result != c.VK_SUCCESS) {
        vk.log.err("{s}: {s}", .{ message, c.ktxErrorString(result) });
        return error.KTXError;
    }
}

// I got how to use KTX from https://github.com/spices-lib/Spices-Engine/
fn formatSupported(
    format: c.VkFormat,
) bool {
    var properties: c.VkFormatProperties = undefined;
    vk.instance.getPhysicalDeviceFormatProperties(
        vk.device.physical_device,
        format,
        &properties,
    );

    const needed_features = c.VK_FORMAT_FEATURE_TRANSFER_DST_BIT | c.VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
    return (properties.optimalTilingFeatures & needed_features) == needed_features;
}

fn availableTargetFormat() c.ktx_transcode_fmt_e {
    const features = vk.device.features.features;

    // Block compression
    if (features.textureCompressionBC == c.VK_TRUE) {
        if (formatSupported(c.VK_FORMAT_BC7_SRGB_BLOCK)) {
            return c.KTX_TTF_BC7_RGBA;
        }

        if (formatSupported(c.VK_FORMAT_BC3_SRGB_BLOCK)) {
            return c.KTX_TTF_BC3_RGBA;
        }
    }

    // Adaptive scalable texture compression
    if (features.textureCompressionASTC_LDR == c.VK_TRUE) {
        if (formatSupported(c.VK_FORMAT_ASTC_4x4_SRGB_BLOCK)) {
            return c.KTX_TTF_ASTC_4x4_RGBA;
        }
    }

    // Ericsson texture compression
    if (features.textureCompressionETC2 == c.VK_TRUE) {
        if (formatSupported(c.VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK)) {
            return c.KTX_TTF_ETC2_RGBA;
        }
    }

    return c.KTX_TTF_RGBA32;
}

fn optimalTilingCallback(
    mip_level: c_int,
    face: c_int,
    width: c_int,
    height: c_int,
    depth: c_int,
    face_lod_size: c.ktx_uint64_t,
    _: ?*anyopaque,
    user_data: ?*anyopaque,
) callconv(.c) c.KTX_error_code {
    var ud: *UserCallbackDataOptimal = @ptrCast(@alignCast(user_data));

    // Set up copy to destination region in final image
    ud.regions[ud.region_index].bufferOffset = ud.offset;
    ud.offset += @intCast(face_lod_size);

    // These 2 are expressed in texels.
    ud.regions[ud.region_index].bufferRowLength = 0;
    ud.regions[ud.region_index].bufferImageHeight = 0;
    ud.regions[ud.region_index].imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    ud.regions[ud.region_index].imageSubresource.mipLevel = @intCast(mip_level);
    ud.regions[ud.region_index].imageSubresource.baseArrayLayer = @intCast(face);
    ud.regions[ud.region_index].imageSubresource.layerCount = ud.num_layers * ud.num_faces;
    ud.regions[ud.region_index].imageOffset.x = 0;
    ud.regions[ud.region_index].imageOffset.y = 0;
    ud.regions[ud.region_index].imageOffset.z = 0;
    ud.regions[ud.region_index].imageExtent.width = @intCast(width);
    ud.regions[ud.region_index].imageExtent.height = @intCast(height);
    ud.regions[ud.region_index].imageExtent.depth = @intCast(depth);
    ud.region_index += 1;

    return c.KTX_SUCCESS;
}

fn linearTilingCallback(
    mip_level: c_int,
    face: c_int,
    _: c_int,
    _: c_int,
    _: c_int,
    face_lod_size: c.ktx_uint64_t,
    pixels: ?*anyopaque,
    user_data: ?*anyopaque,
) callconv(.c) c.KTX_error_code {
    var ud: *UserCallbackDataLinear = @ptrCast(@alignCast(user_data));

    var sub_res = std.mem.zeroInit(c.VkImageSubresource, .{
        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
        .mipLevel = @as(u32, @intCast(mip_level)),
        .arrayLayer = @as(u32, @intCast(face)),
    });

    // Get sub resources layout. Includes row pitch, size, offsets, etc.
    var sub_res_layout: c.VkSubresourceLayout = undefined;
    vk.device.getImageSubresourceLayout(ud.dest_image, &sub_res, &sub_res_layout);

    // Copies all images of the miplevel (for array & 3d) or a single face.
    const pixels_data = @as([*c]const u8, @ptrCast(pixels));
    @memcpy(
        ud.dest[sub_res_layout.offset .. sub_res_layout.offset + face_lod_size],
        pixels_data[0..face_lod_size],
    );

    return c.KTX_SUCCESS;
}

fn generateMipmaps(
    command_buffer: c.VkCommandBuffer,
    image: c.VkImage,
    width: u32,
    height: u32,
    depth: u32,
    layer_count: u32,
    level_count: u32,
    blit_filter: c.VkFilter,
    initial_layout: c.VkImageLayout,
) !void {
    const subresource_range = c.VkImageSubresourceRange{
        .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
        .baseMipLevel = 0,
        .levelCount = 1,
        .baseArrayLayer = 0,
        .layerCount = layer_count,
    };

    // Transition base level to SRC_OPTIMAL for blitting.
    try vk.images.setImageLayout(
        command_buffer,
        image,
        initial_layout,
        c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        subresource_range,
    );

    for (1..level_count) |i| {
        var image_blit = std.mem.zeroes(c.VkImageBlit);

        // Source
        image_blit.srcSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        image_blit.srcSubresource.layerCount = layer_count;
        image_blit.srcSubresource.mipLevel = @intCast(i - 1);
        image_blit.srcOffsets[1].x = @intCast(@max(1, width >> @intCast((i - 1))));
        image_blit.srcOffsets[1].y = @intCast(@max(1, height >> @intCast((i - 1))));
        image_blit.srcOffsets[1].z = @intCast(@max(1, depth >> @intCast((i - 1))));

        // Destination
        image_blit.dstSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        image_blit.dstSubresource.layerCount = 1;
        image_blit.dstSubresource.mipLevel = @intCast(i);
        image_blit.dstOffsets[1].x = @intCast(@max(1, width >> @intCast(i)));
        image_blit.dstOffsets[1].y = @intCast(@max(1, height >> @intCast(i)));
        image_blit.dstOffsets[1].z = @intCast(@max(1, depth >> @intCast(i)));

        var mip_sub_range = std.mem.zeroes(c.VkImageSubresourceRange);
        mip_sub_range.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        mip_sub_range.baseMipLevel = @intCast(i);
        mip_sub_range.levelCount = 1;
        mip_sub_range.layerCount = layer_count;

        // Transiton current mip level to transfer dest
        try vk.images.setImageLayout(
            command_buffer,
            image,
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            mip_sub_range,
        );

        vk.device.cmdBlitImage(
            command_buffer,
            image,
            c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            image,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &image_blit,
            blit_filter,
        );

        // Transiton current mip level to transfer source for read in
        // next iteration.
        try vk.images.setImageLayout(
            command_buffer,
            image,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            mip_sub_range,
        );
    }
}

fn prepareTextureParams(args: PrepareTextureParams) !TextureParams {
    var create_flags: c.VkImageCreateFlags = 0;
    var num_image_layers = args.num_image_layers;
    if (args.is_cubemap) {
        num_image_layers *= 6;
        create_flags = c.VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT;
    }

    var image_type: c.VkImageType = undefined;
    var view_type: c.VkImageViewType = undefined;
    switch (args.num_dimensions) {
        1 => {
            image_type = c.VK_IMAGE_TYPE_1D;
            view_type = if (args.is_array) c.VK_IMAGE_VIEW_TYPE_1D_ARRAY else c.VK_IMAGE_VIEW_TYPE_1D;
        },
        2 => {
            image_type = c.VK_IMAGE_TYPE_2D;
            if (args.is_cubemap) {
                view_type = if (args.is_array) c.VK_IMAGE_VIEW_TYPE_CUBE_ARRAY else c.VK_IMAGE_VIEW_TYPE_CUBE;
            } else {
                view_type = if (args.is_array) c.VK_IMAGE_VIEW_TYPE_2D_ARRAY else c.VK_IMAGE_VIEW_TYPE_2D;
            }
        },
        3 => {
            image_type = c.VK_IMAGE_TYPE_3D;
            view_type = c.VK_IMAGE_VIEW_TYPE_3D;
        },
        else => {
            vk.log.err("Unsupported texture dimensions: {d}", .{args.num_dimensions});
            return error.TextureDimensionsError;
        },
    }

    const format = args.format;
    if (format == c.VK_FORMAT_UNDEFINED) {
        vk.log.err("Texture has undefined format", .{});
        return error.TextureFormatError;
    }

    var usage_flags = args.usage_flags;
    if (args.tiling == c.VK_IMAGE_TILING_OPTIMAL) {
        usage_flags |= c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    }

    if (args.generate_mipmaps) {
        usage_flags |= c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    }

    var image_format_properties: c.VkImageFormatProperties = undefined;
    try vk.instance.getPhysicalDeviceImageFormatProperties(
        vk.device.physical_device,
        format,
        image_type,
        args.tiling,
        @intCast(usage_flags),
        create_flags,
        &image_format_properties,
    );

    if (args.num_image_layers > image_format_properties.maxArrayLayers) {
        vk.log.err("Texture has too many layers: {d}", .{args.num_image_layers});
        return error.TextureLayersError;
    }

    var num_image_levels: u32 = undefined;
    var blit_filter: c.VkFilter = c.VK_FILTER_LINEAR;
    if (args.generate_mipmaps) {
        const needed_features: c.VkFormatFeatureFlags = c.VK_FORMAT_FEATURE_BLIT_DST_BIT | c.VK_FORMAT_FEATURE_BLIT_SRC_BIT;
        var format_properties: c.VkFormatProperties = undefined;
        vk.instance.getPhysicalDeviceFormatProperties(
            vk.device.physical_device,
            format,
            &format_properties,
        );

        var format_features_flags: c.VkFormatFeatureFlags = 0;
        if (args.tiling == c.VK_IMAGE_TILING_OPTIMAL) {
            format_features_flags = format_properties.optimalTilingFeatures;
        } else {
            format_features_flags = format_properties.linearTilingFeatures;
        }

        if ((format_features_flags & needed_features) != needed_features) {
            vk.log.err("Texture format does not support blitting", .{});
            return error.TextureFormatError;
        }

        if ((format_features_flags & c.VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT) != 0) {
            blit_filter = c.VK_FILTER_LINEAR;
        } else {
            blit_filter = c.VK_FILTER_NEAREST; // XXX INVALID_OP?
        }

        const max_dim = @max(@max(args.width, args.height), args.depth);
        num_image_levels = @intFromFloat(@floor(@as(f32, @floatFromInt(std.math.log2(max_dim)))) + 1);
    } else {
        num_image_levels = args.num_image_levels;
    }

    if (num_image_levels > image_format_properties.maxMipLevels) {
        vk.log.err("Texture has too many mip levels: {d}", .{num_image_levels});
        return error.TextureMipLevelsError;
    }

    return .{
        .tiling = args.tiling,
        .format = args.format,
        .width = args.width,
        .height = args.height,
        .depth = args.depth,
        .num_image_levels = num_image_levels,
        .num_image_layers = num_image_layers,
        .usage_flags = usage_flags,
        .blit_filter = blit_filter,
        .final_layout = args.final_layout,
        .view_type = view_type,
        .create_flags = create_flags,
    };
}

pub fn tilingFromGfxTextureTiling(tiling: gfx.TextureTiling) c.VkImageTiling {
    switch (tiling) {
        .optimal => return c.VK_IMAGE_TILING_OPTIMAL,
        .linear => return c.VK_IMAGE_TILING_LINEAR,
    }
}

fn createTexture(
    image: vk.images.Image,
    params: TextureParams,
    debug_name: ?[]const u8,
) !gfx.TextureHandle {
    const texture_image_view = try vk.images.createViewInternal(
        image.image,
        params.format,
        params.view_type,
        c.VK_IMAGE_ASPECT_COLOR_BIT,
        params.num_image_levels,
        params.num_image_layers,
    );
    errdefer vk.images.destroyViewInternal(texture_image_view);

    vk.log.debug("Created texture:", .{});
    if (debug_name) |name| {
        try vk.debug.setObjectName(c.VK_OBJECT_TYPE_IMAGE, image.image, name);
        vk.log.debug("  - Name: {s}", .{name});
    }
    vk.log.debug("  - Width: {d}", .{params.width});
    vk.log.debug("  - Height: {d}", .{params.height});
    vk.log.debug("  - Depth: {d}", .{params.depth});
    vk.log.debug("  - Level count: {d}", .{params.num_image_levels});
    vk.log.debug("  - Layer count: {d}", .{params.num_image_layers});
    vk.log.debug("  - Format: {s}", .{c.string_VkFormat(params.format)});
    vk.log.debug("  - Image layout: {s}", .{c.string_VkImageLayout(params.final_layout)});
    vk.log.debug("  - View type: {s}", .{c.string_VkImageViewType(params.view_type)});

    var sampler_info = c.VkSamplerCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = c.VK_FILTER_LINEAR,
        .minFilter = c.VK_FILTER_LINEAR,
        .addressModeU = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = c.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
        .unnormalizedCoordinates = c.VK_FALSE,
        .compareEnable = c.VK_FALSE,
        .compareOp = c.VK_COMPARE_OP_ALWAYS,
        .mipmapMode = c.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .mipLodBias = 0.0,
        .minLod = 0.0,
        .maxLod = @floatFromInt(params.num_image_levels),
    };

    if (vk.device.features.features.samplerAnisotropy == c.VK_TRUE) {
        sampler_info.anisotropyEnable = c.VK_TRUE;
        sampler_info.maxAnisotropy = vk.device.properties.limits.maxSamplerAnisotropy;
    }

    var sampler: c.VkSampler = undefined;
    try vk.device.createSampler(&sampler_info, &sampler);
    errdefer vk.device.destroySampler(sampler);

    vk.log.debug("Created sampler:", .{});
    if (debug_name) |name| {
        try vk.debug.setObjectName(c.VK_OBJECT_TYPE_SAMPLER, sampler, name);
        vk.log.debug("  - Name: {s}", .{name});
    }
    vk.log.debug("  - Mag filter: {s}", .{c.string_VkFilter(sampler_info.magFilter)});
    vk.log.debug("  - Min filter: {s}", .{c.string_VkFilter(sampler_info.minFilter)});
    vk.log.debug("  - Address mode U: {s}", .{c.string_VkSamplerAddressMode(sampler_info.addressModeU)});
    vk.log.debug("  - Address mode V: {s}", .{c.string_VkSamplerAddressMode(sampler_info.addressModeV)});
    vk.log.debug("  - Address mode W: {s}", .{c.string_VkSamplerAddressMode(sampler_info.addressModeW)});
    vk.log.debug("  - Border color: {s}", .{c.string_VkBorderColor(sampler_info.borderColor)});
    vk.log.debug("  - Unnormalized coordinates: {}", .{sampler_info.unnormalizedCoordinates == c.VK_TRUE});
    vk.log.debug("  - Compare enable: {}", .{sampler_info.compareEnable == c.VK_TRUE});
    vk.log.debug("  - Compare op: {s}", .{c.string_VkCompareOp(sampler_info.compareOp)});
    vk.log.debug("  - Mipmap mode: {s}", .{c.string_VkSamplerMipmapMode(sampler_info.mipmapMode)});
    vk.log.debug("  - Mip lod bias: {d}", .{sampler_info.mipLodBias});
    vk.log.debug("  - Min lod: {d}", .{sampler_info.minLod});
    vk.log.debug("  - Max lod: {d}", .{sampler_info.maxLod});
    vk.log.debug("  - Anisotropy enable: {}", .{sampler_info.anisotropyEnable == c.VK_TRUE});
    vk.log.debug("  - Max anisotropy: {d}", .{sampler_info.maxAnisotropy});

    const texture = try vk.gpa.create(Texture);
    errdefer vk.gpa.destroy(texture);

    texture.* = .{
        .image = image,
        .image_layout = params.final_layout,
        .image_view = texture_image_view,
        .sampler = sampler,
        .debug_name = if (debug_name) |name|
            try vk.gpa.dupe(u8, name)
        else
            null,
    };

    return .{ .handle = @ptrCast(texture) };
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _textures_to_destroy = .init(vk.gpa);
    errdefer _textures_to_destroy.deinit();
}

pub fn deinit() void {
    _textures_to_destroy.deinit();
}

pub fn create(
    transfer_command_pool: c.VkCommandPool,
    graphics_command_pool: c.VkCommandPool,
    transfer_queue: c.VkQueue,
    graphics_queue: c.VkQueue,
    reader: std.io.AnyReader,
    size: u32,
    options: gfx.TextureOptions,
) !gfx.TextureHandle {
    const params = try prepareTextureParams(.{
        .format = vk.vulkanFormatFromGfxImageFormat(options.format),
        .width = options.width,
        .height = options.height,
        .depth = options.depth,
        .num_image_layers = options.array_layers,
        .tiling = tilingFromGfxTextureTiling(options.tiling),
        .is_cubemap = options.is_cubemap,
        .is_array = options.is_array,
        .generate_mipmaps = options.generate_mipmaps,
    });

    const command_pool = if (options.generate_mipmaps)
        graphics_command_pool
    else
        transfer_command_pool;

    const queue = if (options.generate_mipmaps)
        graphics_queue
    else
        transfer_queue;

    var image: vk.images.Image = undefined;
    if (params.tiling == c.VK_IMAGE_TILING_OPTIMAL) {
        var staging_buffer = try vk.buffers.createBuffer(
            size,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            options.debug_name,
        );
        defer vk.buffers.destroyBuffer(&staging_buffer);

        var mapped_staging_buffer: [*c]u8 = undefined;
        try vk.device.mapMemory(
            staging_buffer.memory,
            0,
            size,
            0,
            @ptrCast(&mapped_staging_buffer),
        );
        defer vk.device.unmapMemory(staging_buffer.memory);

        if (try reader.readAll(mapped_staging_buffer[0..size]) != size) {
            vk.log.err("Failed to read texture data", .{});
            return error.TextureDataError;
        }

        image = try vk.images.createInternal(
            options.width,
            options.height,
            options.depth,
            params.format,
            params.create_flags,
            params.num_image_levels,
            params.num_image_layers,
            c.VK_IMAGE_TILING_OPTIMAL,
            @intCast(params.usage_flags),
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            c.VK_SAMPLE_COUNT_1_BIT,
        );
        errdefer vk.images.destroyInternal(image);

        const command_buffer =
            try vk.command_buffers.beginSingleTimeCommands(command_pool);
        defer vk.command_buffers.endSingleTimeCommands(
            command_pool,
            command_buffer,
            queue,
        );

        var region = std.mem.zeroes(c.VkBufferImageCopy);
        region.bufferOffset = 0;
        region.bufferRowLength = 0;
        region.bufferImageHeight = 0;
        region.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.mipLevel = 0;
        region.imageSubresource.baseArrayLayer = 0;
        region.imageSubresource.layerCount = params.num_image_layers;
        region.imageOffset.x = 0;
        region.imageOffset.y = 0;
        region.imageOffset.z = 0;
        region.imageExtent.width = options.width;
        region.imageExtent.height = options.height;
        region.imageExtent.depth = options.depth;

        const subresource_range = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = params.num_image_levels,
            .baseArrayLayer = 0,
            .layerCount = params.num_image_layers,
        };

        try vk.images.setImageLayout(
            command_buffer,
            image.image,
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            subresource_range,
        );

        vk.device.cmdCopyBufferToImage(
            command_buffer,
            staging_buffer.buffer,
            image.image,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        if (options.generate_mipmaps) {
            try generateMipmaps(
                command_buffer,
                image.image,
                options.width,
                options.height,
                options.depth,
                params.num_image_layers,
                params.num_image_levels,
                params.blit_filter,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            );

            try vk.images.setImageLayout(
                command_buffer,
                image.image,
                c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                params.final_layout,
                c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = params.num_image_levels,
                    .baseArrayLayer = 0,
                    .layerCount = params.num_image_layers,
                },
            );
        } else {
            // Transition image layout to finalLayout after all mip levels
            // have been copied.
            // In this case numImageLevels == This->numLevels
            //subresourceRange.levelCount = numImageLevels;
            try vk.images.setImageLayout(
                command_buffer,
                image.image,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                params.final_layout,
                subresource_range,
            );
        }
    } else {
        image = try vk.images.createInternal(
            options.width,
            options.height,
            options.depth,
            params.format,
            params.create_flags,
            params.num_image_levels,
            params.num_image_layers,
            c.VK_IMAGE_TILING_LINEAR,
            @intCast(params.usage_flags),
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            c.VK_SAMPLE_COUNT_1_BIT,
        );
        errdefer vk.images.destroyInternal(image);

        var mapped_data: [*c]u8 = undefined;
        try vk.device.mapMemory(
            image.memory,
            0,
            image.size,
            0,
            @ptrCast(&mapped_data),
        );
        defer vk.device.unmapMemory(image.memory);

        if (try reader.readAll(mapped_data[0..size]) != size) {
            vk.log.err("Failed to read texture data", .{});
            return error.TextureDataError;
        }
        const command_buffer =
            try vk.command_buffers.beginSingleTimeCommands(command_pool);
        defer vk.command_buffers.endSingleTimeCommands(
            command_pool,
            command_buffer,
            queue,
        );

        if (options.generate_mipmaps) {
            try generateMipmaps(
                command_buffer,
                image.image,
                options.width,
                options.height,
                options.depth,
                params.num_image_layers,
                params.num_image_levels,
                params.blit_filter,
                c.VK_IMAGE_LAYOUT_PREINITIALIZED,
            );

            try vk.images.setImageLayout(
                command_buffer,
                image.image,
                c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                params.final_layout,
                c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = params.num_image_levels,
                    .baseArrayLayer = 0,
                    .layerCount = params.num_image_layers,
                },
            );
        } else {
            const subresource_range = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = params.num_image_levels,
                .baseArrayLayer = 0,
                .layerCount = params.num_image_layers,
            };

            try vk.images.setImageLayout(
                command_buffer,
                image.image,
                c.VK_IMAGE_LAYOUT_PREINITIALIZED,
                params.final_layout,
                subresource_range,
            );
        }
    }
    errdefer vk.images.destroyInternal(image);

    return try createTexture(image, params, options.debug_name);
}

pub fn createFromKTX(
    command_pool: c.VkCommandPool,
    transfer_queue: c.VkQueue,
    reader: std.io.AnyReader,
    size: u32,
    options: gfx.TextureKTXOptions,
) !gfx.TextureHandle {
    // TODO: use a specialized arena?
    // TODO: Optimize this without using a temporary buffer?
    const data = try vk.arena.alloc(u8, size);
    if (try reader.readAll(data) != size) {
        vk.log.err("Failed to read KTX texture data", .{});
        return error.KTXError;
    }

    var ktx_texture: *c.ktxTexture2 = undefined;
    try checkKtxError(
        "Failed to create KTX texture",
        c.ktxTexture2_CreateFromMemory(
            data.ptr,
            data.len,
            c.KTX_TEXTURE_CREATE_LOAD_IMAGE_DATA_BIT,
            @ptrCast(&ktx_texture),
        ),
    );
    defer c.ktxTexture2_Destroy(ktx_texture);

    if (c.ktxTexture2_NeedsTranscoding(ktx_texture)) {
        const format = availableTargetFormat();
        try checkKtxError(
            "Failed to transcode KTX texture",
            c.ktxTexture2_TranscodeBasis(ktx_texture, format, 0),
        );
    }

    const params = try prepareTextureParams(.{
        .format = ktx_texture.vkFormat,
        .width = ktx_texture.baseWidth,
        .height = ktx_texture.baseHeight,
        .depth = ktx_texture.baseDepth,
        .num_image_layers = ktx_texture.numLayers,
        .num_image_levels = ktx_texture.numLevels,
        .num_dimensions = ktx_texture.numDimensions,
        .is_cubemap = ktx_texture.isCubemap,
        .is_array = ktx_texture.isArray,
        .generate_mipmaps = ktx_texture.generateMipmaps,
    });

    var image: vk.images.Image = undefined;
    if (params.tiling == c.VK_IMAGE_TILING_OPTIMAL) {
        const num_copy_regions = ktx_texture.numLevels;
        const texture_size = ktxTexture2_GetDataSizeUncompressed(ktx_texture);

        const copy_regions = try vk.arena.alloc(c.VkBufferImageCopy, num_copy_regions);

        var staging_buffer = try vk.buffers.createBuffer(
            texture_size,
            c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            options.debug_name,
        );
        defer vk.buffers.destroyBuffer(&staging_buffer);

        var mapped_staging_buffer: [*c]u8 = undefined;
        try vk.device.mapMemory(
            staging_buffer.memory,
            0,
            texture_size,
            0,
            @ptrCast(&mapped_staging_buffer),
        );
        defer vk.device.unmapMemory(staging_buffer.memory);

        @memcpy(
            mapped_staging_buffer[0..texture_size],
            ktx_texture.pData[0..ktx_texture.dataSize],
        );

        var user_data = UserCallbackDataOptimal{
            .regions = copy_regions,
            .region_index = 0,
            .offset = 0,
            .num_faces = ktx_texture.numFaces,
            .num_layers = ktx_texture.numLayers,
        };

        try checkKtxError(
            "Failed to iterate KTX texture levels",
            ktxTexture2_IterateLevels(
                ktx_texture,
                &optimalTilingCallback,
                @ptrCast(&user_data),
            ),
        );

        image = try vk.images.createInternal(
            ktx_texture.baseWidth,
            ktx_texture.baseHeight,
            ktx_texture.baseDepth,
            params.format,
            params.create_flags,
            params.num_image_levels,
            params.num_image_layers,
            c.VK_IMAGE_TILING_OPTIMAL,
            @intCast(params.usage_flags),
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            c.VK_SAMPLE_COUNT_1_BIT,
        );
        errdefer vk.images.destroyInternal(image);

        const command_buffer =
            try vk.command_buffers.beginSingleTimeCommands(command_pool);
        defer vk.command_buffers.endSingleTimeCommands(
            command_pool,
            command_buffer,
            transfer_queue,
        );

        vk.debug.beginCommandBufferLabel(
            command_buffer,
            try std.fmt.allocPrint(
                vk.arena,
                "Copy buffer to image {s}",
                .{
                    if (options.debug_name) |label|
                        label
                    else
                        "-",
                },
            ),
            types.Colors.DarkSlateBlue,
        );
        defer vk.debug.endCommandBufferLabel(command_buffer);

        const subresource_range = c.VkImageSubresourceRange{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = params.num_image_levels,
            .baseArrayLayer = 0,
            .layerCount = params.num_image_layers,
        };

        try vk.images.setImageLayout(
            command_buffer,
            image.image,
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            subresource_range,
        );

        vk.device.cmdCopyBufferToImage(
            command_buffer,
            staging_buffer.buffer,
            image.image,
            c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            @intCast(num_copy_regions),
            copy_regions.ptr,
        );

        if (ktx_texture.generateMipmaps) {
            try generateMipmaps(
                command_buffer,
                image.image,
                ktx_texture.baseWidth,
                ktx_texture.baseHeight,
                ktx_texture.baseDepth,
                params.num_image_layers,
                params.num_image_levels,
                params.blit_filter,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            );
        } else {
            // Transition image layout to finalLayout after all mip levels
            // have been copied.
            // In this case numImageLevels == This->numLevels
            //subresourceRange.levelCount = numImageLevels;
            try vk.images.setImageLayout(
                command_buffer,
                image.image,
                c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                params.final_layout,
                subresource_range,
            );
        }
    } else {
        image = try vk.images.createInternal(
            ktx_texture.baseWidth,
            ktx_texture.baseHeight,
            ktx_texture.baseDepth,
            params.format,
            params.create_flags,
            params.num_image_levels,
            params.num_image_layers,
            c.VK_IMAGE_TILING_LINEAR,
            @intCast(params.usage_flags),
            c.VK_IMAGE_LAYOUT_UNDEFINED,
            c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            c.VK_SAMPLE_COUNT_1_BIT,
        );
        errdefer vk.images.destroyInternal(image);

        var user_data = UserCallbackDataLinear{
            .dest_image = image.image,
            .dest = undefined,
        };

        try vk.device.mapMemory(
            image.memory,
            0,
            image.size,
            0,
            @ptrCast(&user_data.dest),
        );
        defer vk.device.unmapMemory(image.memory);

        try checkKtxError(
            "Failed to iterate KTX texture levels",
            c.ktxTexture_IterateLevelFaces(
                @ptrCast(ktx_texture),
                &linearTilingCallback,
                @ptrCast(&user_data),
            ),
        );

        const command_buffer =
            try vk.command_buffers.beginSingleTimeCommands(command_pool);
        defer vk.command_buffers.endSingleTimeCommands(
            command_pool,
            command_buffer,
            transfer_queue,
        );

        vk.debug.beginCommandBufferLabel(
            command_buffer,
            try std.fmt.allocPrint(
                vk.arena,
                "Copy buffer to image {s}",
                .{
                    if (options.debug_name) |label|
                        label
                    else
                        "-",
                },
            ),
            types.Colors.DarkSlateBlue,
        );
        defer vk.debug.endCommandBufferLabel(command_buffer);

        if (ktx_texture.generateMipmaps) {
            try generateMipmaps(
                command_buffer,
                image.image,
                ktx_texture.baseWidth,
                ktx_texture.baseHeight,
                ktx_texture.baseDepth,
                params.num_image_layers,
                params.num_image_levels,
                params.blit_filter,
                c.VK_IMAGE_LAYOUT_PREINITIALIZED,
            );
        } else {
            const subresource_range = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = params.num_image_levels,
                .baseArrayLayer = 0,
                .layerCount = params.num_image_layers,
            };

            try vk.images.setImageLayout(
                command_buffer,
                image.image,
                c.VK_IMAGE_LAYOUT_PREINITIALIZED,
                params.final_layout,
                subresource_range,
            );
        }
    }
    errdefer vk.images.destroyInternal(image);

    return try createTexture(image, params, options.debug_name);
}

pub fn destroy(handle: gfx.TextureHandle) void {
    const texture = get(handle);
    _textures_to_destroy.append(texture) catch |err| {
        vk.log.err("Failed to append texture to destroy list: {any}", .{err});
        return;
    };

    if (texture.debug_name) |name| {
        vk.log.debug("Texture '{s}' queued for destruction", .{name});
    }
}

pub fn destroyPendingResources() void {
    for (_textures_to_destroy.items) |texture| {
        vk.device.destroySampler(texture.sampler);
        vk.images.destroyViewInternal(texture.image_view);
        vk.images.destroyInternal(texture.image);
        if (texture.debug_name) |name| {
            vk.log.debug("Texture '{s}' destroyed", .{name});
            vk.gpa.free(name);
        }
        vk.gpa.destroy(texture);
    }
    _textures_to_destroy.clearRetainingCapacity();
}

pub inline fn get(handle: gfx.TextureHandle) *Texture {
    return @ptrCast(@alignCast(handle.handle));
}
