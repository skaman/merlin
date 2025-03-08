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
    device: *const vk.Device,
    format: c.VkFormat,
) bool {
    var properties: c.VkFormatProperties = undefined;
    device.getPhysicalDeviceFormatProperties(format, &properties);

    const needed_features = c.VK_FORMAT_FEATURE_TRANSFER_DST_BIT | c.VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT;
    return (properties.optimalTilingFeatures & needed_features) == needed_features;
}

fn get_available_target_format(device: *const vk.Device) c.ktx_transcode_fmt_e {
    const features = device.features.features;

    // Block compression
    if (features.textureCompressionBC == c.VK_TRUE) {
        if (format_supported(device, c.VK_FORMAT_BC7_SRGB_BLOCK)) {
            return c.KTX_TTF_BC7_RGBA;
        }

        if (format_supported(device, c.VK_FORMAT_BC3_SRGB_BLOCK)) {
            return c.KTX_TTF_BC3_RGBA;
        }
    }

    // Adaptive scalable texture compression
    if (features.textureCompressionASTC_LDR == c.VK_TRUE) {
        if (format_supported(device, c.VK_FORMAT_ASTC_4x4_SRGB_BLOCK)) {
            return c.KTX_TTF_ASTC_4x4_RGBA;
        }
    }

    // Ericsson texture compression
    if (features.textureCompressionETC2 == c.VK_TRUE) {
        if (format_supported(device, c.VK_FORMAT_ETC2_R8G8B8A8_SRGB_BLOCK)) {
            return c.KTX_TTF_ETC2_RGBA;
        }
    }

    return c.KTX_TTF_RGBA32;
}

pub const Texture = struct {
    const Self = @This();

    const MaxBufferSize = 256 * 1024 * 1024;

    device: *const vk.Device,
    ktx_texture: c.ktxVulkanTexture,

    pub fn init(
        arena_allocator: std.mem.Allocator,
        device: *const vk.Device,
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
            const format = get_available_target_format(device);
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
                device.instance.handle,
                device.physical_device,
                device.device,
                g_transfer_queue,
                command_pool.handle,
                device.instance.allocation_callbacks,
                &device.ktx_vulkan_functions,
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

        vk.log.debug("KTX texture uploaded:", .{});
        vk.log.debug("  - Width: {d}", .{texture.width});
        vk.log.debug("  - Height: {d}", .{texture.height});
        vk.log.debug("  - Depth: {d}", .{texture.depth});
        vk.log.debug("  - Level count: {d}", .{texture.levelCount});
        vk.log.debug("  - Layer count: {d}", .{texture.layerCount});
        vk.log.debug("  - Format: {s}", .{c.string_VkFormat(texture.imageFormat)});
        vk.log.debug("  - Image layout: {s}", .{c.string_VkImageLayout(texture.imageLayout)});
        vk.log.debug("  - View type: {s}", .{c.string_VkImageViewType(texture.viewType)});

        return .{
            .device = device,
            .ktx_texture = texture,
        };
    }

    pub fn deinit(self: *Self) void {
        c.ktxVulkanTexture_Destruct(
            &self.ktx_texture,
            self.device.device,
            self.device.instance.allocation_callbacks,
        );
    }
};
