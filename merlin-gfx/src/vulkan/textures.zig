const std = @import("std");

const utils = @import("merlin_utils");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Texture = struct {
    ktx_texture: c.ktxVulkanTexture,
    image_view: c.VkImageView,
    sampler: c.VkSampler,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var textures: utils.HandleArray(
    gfx.TextureHandle,
    Texture,
    gfx.MaxTextureHandles,
) = undefined;

var texture_handles: utils.HandlePool(
    gfx.TextureHandle,
    gfx.MaxTextureHandles,
) = undefined;

var textures_to_destroy: [gfx.MaxTextureHandles]Texture = undefined;
var textures_to_destroy_count: u32 = 0;

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

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    texture_handles = .init();
    textures_to_destroy_count = 0;
}

pub fn deinit() void {
    texture_handles.deinit();
}

pub fn create(
    command_pool: c.VkCommandPool,
    transfer_queue: c.VkQueue,
    loader: utils.loaders.TextureLoader,
) !gfx.TextureHandle {
    // TODO: use a specialized arena?
    // TODO: Optimize this without using a temporary buffer?
    const data = try loader.read(vk.arena);

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

    var vulkan_device_info: c.ktxVulkanDeviceInfo = undefined;
    try checkKtxError(
        "Failed to create KTX Vulkan device info",
        c.ktxVulkanDeviceInfo_ConstructEx(
            &vulkan_device_info,
            vk.instance.handle,
            vk.device.physical_device,
            vk.device.handle,
            transfer_queue,
            command_pool,
            vk.instance.allocation_callbacks,
            &vk.device.ktx_vulkan_functions,
        ),
    );
    defer c.ktxVulkanDeviceInfo_Destruct(&vulkan_device_info);

    var texture: c.ktxVulkanTexture = undefined;
    try checkKtxError(
        "Failed to upload KTX texture",
        c.ktxTexture2_VkUploadEx(
            ktx_texture,
            &vulkan_device_info,
            &texture,
            c.VK_IMAGE_TILING_OPTIMAL,
            c.VK_IMAGE_USAGE_SAMPLED_BIT,
            c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        ),
    );
    errdefer c.ktxVulkanTexture_Destruct(
        &texture,
        vk.device.handle,
        vk.instance.allocation_callbacks,
    );

    vk.log.debug("KTX texture uploaded:", .{});
    vk.log.debug("  - Width: {d}", .{texture.width});
    vk.log.debug("  - Height: {d}", .{texture.height});
    vk.log.debug("  - Depth: {d}", .{texture.depth});
    vk.log.debug("  - Level count: {d}", .{texture.levelCount});
    vk.log.debug("  - Layer count: {d}", .{texture.layerCount});
    vk.log.debug("  - Format: {s}", .{c.string_VkFormat(texture.imageFormat)});
    vk.log.debug("  - Image layout: {s}", .{c.string_VkImageLayout(texture.imageLayout)});
    vk.log.debug("  - View type: {s}", .{c.string_VkImageViewType(texture.viewType)});

    const texture_image_view = try vk.image.createView(
        texture.image,
        texture.imageFormat,
        texture.viewType,
        c.VK_IMAGE_ASPECT_COLOR_BIT,
        texture.levelCount,
        texture.layerCount,
    );
    errdefer vk.image.destroyView(texture_image_view);

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
        .maxLod = @floatFromInt(texture.levelCount),
    };

    if (vk.device.features.features.samplerAnisotropy == c.VK_TRUE) {
        sampler_info.anisotropyEnable = c.VK_TRUE;
        sampler_info.maxAnisotropy = vk.device.properties.limits.maxSamplerAnisotropy;
    }

    var sampler: c.VkSampler = undefined;
    try vk.device.createSampler(&sampler_info, &sampler);
    errdefer vk.device.destroySampler(sampler);

    vk.log.debug("Created sampler:", .{});
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

    const handle = try texture_handles.create();
    errdefer texture_handles.destroy(handle);

    textures.setValue(
        handle,
        .{
            .ktx_texture = texture,
            .image_view = texture_image_view,
            .sampler = sampler,
        },
    );

    vk.log.debug("Created texture:", .{});
    vk.log.debug("  - Handle: {d}", .{handle});

    return handle;
}

pub fn destroy(handle: gfx.TextureHandle) void {
    textures_to_destroy[textures_to_destroy_count] = textures.value(handle);
    textures_to_destroy_count += 1;

    texture_handles.destroy(handle);

    vk.log.debug("Destroyed texture with handle {d}", .{handle});
}

pub fn destroyPendingResources() void {
    for (0..textures_to_destroy_count) |i| {
        const texture = &textures_to_destroy[i];
        vk.device.destroySampler(texture.sampler);
        vk.image.destroyView(texture.image_view);

        c.ktxVulkanTexture_Destruct(
            &texture.ktx_texture,
            vk.device.handle,
            vk.instance.allocation_callbacks,
        );
    }
    textures_to_destroy_count = 0;
}

pub inline fn getImageLayout(handle: gfx.TextureHandle) c.VkImageLayout {
    const texture = textures.valuePtr(handle);
    return texture.ktx_texture.imageLayout;
}

pub inline fn getImageView(handle: gfx.TextureHandle) c.VkImageView {
    const texture = textures.valuePtr(handle);
    return texture.image_view;
}

pub inline fn getSampler(handle: gfx.TextureHandle) c.VkSampler {
    const texture = textures.valuePtr(handle);
    return texture.sampler;
}
