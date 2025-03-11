const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

fn checkKtxError(comptime message: []const u8, result: c.KTX_error_code) !void {
    if (result != c.VK_SUCCESS) {
        vk.log.err("{s}: {s}", .{ message, c.ktxErrorString(result) });
        return error.KTXError;
    }
}

// I got how to use KTX from https://github.com/spices-lib/Spices-Engine/
fn format_supported(
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

fn get_available_target_format() c.ktx_transcode_fmt_e {
    const features = vk.device.features.features;

    // Block compression
    if (features.textureCompressionBC == c.VK_TRUE) {
        if (format_supported(c.VK_FORMAT_BC7_SRGB_BLOCK)) {
            return c.KTX_TTF_BC7_RGBA;
        }

        if (format_supported(c.VK_FORMAT_BC3_SRGB_BLOCK)) {
            return c.KTX_TTF_BC3_RGBA;
        }
    }

    // Adaptive scalable texture compression
    if (features.textureCompressionASTC_LDR == c.VK_TRUE) {
        if (format_supported(c.VK_FORMAT_ASTC_4x4_SRGB_BLOCK)) {
            return c.KTX_TTF_ASTC_4x4_RGBA;
        }
    }

    // Ericsson texture compression
    if (features.textureCompressionETC2 == c.VK_TRUE) {
        if (format_supported(c.VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK)) {
            return c.KTX_TTF_ETC2_RGBA;
        }
    }

    return c.KTX_TTF_RGBA32;
}

pub const Texture = struct {
    const Self = @This();

    const MaxBufferSize = 256 * 1024 * 1024;

    ktx_texture: c.ktxVulkanTexture,
    image_view: c.VkImageView,
    sampler: c.VkSampler,

    pub fn init(
        arena_allocator: std.mem.Allocator,
        command_pool: *const vk.CommandPool,
        g_transfer_queue: c.VkQueue,
        reader: std.io.AnyReader,
    ) !Self {
        // TODO: Optimize this without using a temporary buffer?
        const data = try reader.readAllAlloc(
            arena_allocator,
            MaxBufferSize,
        );

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
            const format = get_available_target_format();
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
                g_transfer_queue,
                command_pool.handle,
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

        const view_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = texture.image,
            .viewType = texture.viewType,
            .format = texture.imageFormat,
            .components = c.VkComponentMapping{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = texture.levelCount,
                .baseArrayLayer = 0,
                .layerCount = texture.layerCount,
            },
        };
        var texture_image_view: c.VkImageView = undefined;
        try vk.device.createImageView(&view_info, &texture_image_view);
        errdefer vk.device.destroyImageView(texture_image_view);

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

        return .{
            .ktx_texture = texture,
            .image_view = texture_image_view,
            .sampler = sampler,
        };
    }

    pub fn deinit(self: *Self) void {
        vk.device.destroySampler(self.sampler);
        vk.device.destroyImageView(self.image_view);

        c.ktxVulkanTexture_Destruct(
            &self.ktx_texture,
            vk.device.handle,
            vk.instance.allocation_callbacks,
        );
    }
};
