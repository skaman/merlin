const std = @import("std");

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const Dispatch = struct {
    AcquireNextImageKHR: std.meta.Child(c.PFN_vkAcquireNextImageKHR) = undefined,
    AllocateCommandBuffers: std.meta.Child(c.PFN_vkAllocateCommandBuffers) = undefined,
    AllocateDescriptorSets: std.meta.Child(c.PFN_vkAllocateDescriptorSets) = undefined,
    AllocateMemory: std.meta.Child(c.PFN_vkAllocateMemory) = undefined,
    BeginCommandBuffer: std.meta.Child(c.PFN_vkBeginCommandBuffer) = undefined,
    BindBufferMemory: std.meta.Child(c.PFN_vkBindBufferMemory) = undefined,
    BindImageMemory: std.meta.Child(c.PFN_vkBindImageMemory) = undefined,
    CmdBindDescriptorSets: std.meta.Child(c.PFN_vkCmdBindDescriptorSets) = undefined,
    CmdBindIndexBuffer: std.meta.Child(c.PFN_vkCmdBindIndexBuffer) = undefined,
    CmdBindPipeline: std.meta.Child(c.PFN_vkCmdBindPipeline) = undefined,
    CmdBindVertexBuffers: std.meta.Child(c.PFN_vkCmdBindVertexBuffers) = undefined,
    CmdBlitImage: std.meta.Child(c.PFN_vkCmdBlitImage) = undefined,
    CmdCopyBuffer: std.meta.Child(c.PFN_vkCmdCopyBuffer) = undefined,
    CmdCopyBufferToImage: std.meta.Child(c.PFN_vkCmdCopyBufferToImage) = undefined,
    CmdDraw: std.meta.Child(c.PFN_vkCmdDraw) = undefined,
    CmdDrawIndexed: std.meta.Child(c.PFN_vkCmdDrawIndexed) = undefined,
    CmdPipelineBarrier: std.meta.Child(c.PFN_vkCmdPipelineBarrier) = undefined,
    CmdPushDescriptorSetKHR: std.meta.Child(c.PFN_vkCmdPushDescriptorSetKHR) = undefined,
    CmdPushConstants: std.meta.Child(c.PFN_vkCmdPushConstants) = undefined,
    CmdSetScissor: std.meta.Child(c.PFN_vkCmdSetScissor) = undefined,
    CmdSetViewport: std.meta.Child(c.PFN_vkCmdSetViewport) = undefined,
    CreateBuffer: std.meta.Child(c.PFN_vkCreateBuffer) = undefined,
    CreateCommandPool: std.meta.Child(c.PFN_vkCreateCommandPool) = undefined,
    CreateDescriptorPool: std.meta.Child(c.PFN_vkCreateDescriptorPool) = undefined,
    CreateDescriptorSetLayout: std.meta.Child(c.PFN_vkCreateDescriptorSetLayout) = undefined,
    CreateFence: std.meta.Child(c.PFN_vkCreateFence) = undefined,
    CreateFramebuffer: std.meta.Child(c.PFN_vkCreateFramebuffer) = undefined,
    CreateGraphicsPipelines: std.meta.Child(c.PFN_vkCreateGraphicsPipelines) = undefined,
    CreateImage: std.meta.Child(c.PFN_vkCreateImage) = undefined,
    CreateImageView: std.meta.Child(c.PFN_vkCreateImageView) = undefined,
    CreatePipelineLayout: std.meta.Child(c.PFN_vkCreatePipelineLayout) = undefined,
    CreateSampler: std.meta.Child(c.PFN_vkCreateSampler) = undefined,
    CreateSemaphore: std.meta.Child(c.PFN_vkCreateSemaphore) = undefined,
    CreateShaderModule: std.meta.Child(c.PFN_vkCreateShaderModule) = undefined,
    CreateSwapchainKHR: std.meta.Child(c.PFN_vkCreateSwapchainKHR) = undefined,
    DestroyBuffer: std.meta.Child(c.PFN_vkDestroyBuffer) = undefined,
    DestroyCommandPool: std.meta.Child(c.PFN_vkDestroyCommandPool) = undefined,
    DestroyDescriptorPool: std.meta.Child(c.PFN_vkDestroyDescriptorPool) = undefined,
    DestroyDescriptorSetLayout: std.meta.Child(c.PFN_vkDestroyDescriptorSetLayout) = undefined,
    DestroyDevice: std.meta.Child(c.PFN_vkDestroyDevice) = undefined,
    DestroyFence: std.meta.Child(c.PFN_vkDestroyFence) = undefined,
    DestroyFramebuffer: std.meta.Child(c.PFN_vkDestroyFramebuffer) = undefined,
    DestroyImage: std.meta.Child(c.PFN_vkDestroyImage) = undefined,
    DestroyImageView: std.meta.Child(c.PFN_vkDestroyImageView) = undefined,
    DestroyPipeline: std.meta.Child(c.PFN_vkDestroyPipeline) = undefined,
    DestroyPipelineLayout: std.meta.Child(c.PFN_vkDestroyPipelineLayout) = undefined,
    DestroySampler: std.meta.Child(c.PFN_vkDestroySampler) = undefined,
    DestroySemaphore: std.meta.Child(c.PFN_vkDestroySemaphore) = undefined,
    DestroyShaderModule: std.meta.Child(c.PFN_vkDestroyShaderModule) = undefined,
    DestroySwapchainKHR: std.meta.Child(c.PFN_vkDestroySwapchainKHR) = undefined,
    DeviceWaitIdle: std.meta.Child(c.PFN_vkDeviceWaitIdle) = undefined,
    EndCommandBuffer: std.meta.Child(c.PFN_vkEndCommandBuffer) = undefined,
    FreeCommandBuffers: std.meta.Child(c.PFN_vkFreeCommandBuffers) = undefined,
    FreeDescriptorSets: std.meta.Child(c.PFN_vkFreeDescriptorSets) = undefined,
    FreeMemory: std.meta.Child(c.PFN_vkFreeMemory) = undefined,
    GetBufferMemoryRequirements: std.meta.Child(c.PFN_vkGetBufferMemoryRequirements) = undefined,
    GetDeviceQueue: std.meta.Child(c.PFN_vkGetDeviceQueue) = undefined,
    GetImageMemoryRequirements: std.meta.Child(c.PFN_vkGetImageMemoryRequirements) = undefined,
    GetImageSubresourceLayout: std.meta.Child(c.PFN_vkGetImageSubresourceLayout) = undefined,
    GetSwapchainImagesKHR: std.meta.Child(c.PFN_vkGetSwapchainImagesKHR) = undefined,
    MapMemory: std.meta.Child(c.PFN_vkMapMemory) = undefined,
    QueuePresentKHR: std.meta.Child(c.PFN_vkQueuePresentKHR) = undefined,
    QueueSubmit: std.meta.Child(c.PFN_vkQueueSubmit) = undefined,
    QueueWaitIdle: std.meta.Child(c.PFN_vkQueueWaitIdle) = undefined,
    ResetCommandBuffer: std.meta.Child(c.PFN_vkResetCommandBuffer) = undefined,
    ResetFences: std.meta.Child(c.PFN_vkResetFences) = undefined,
    UnmapMemory: std.meta.Child(c.PFN_vkUnmapMemory) = undefined,
    UpdateDescriptorSets: std.meta.Child(c.PFN_vkUpdateDescriptorSets) = undefined,
    WaitForFences: std.meta.Child(c.PFN_vkWaitForFences) = undefined,
    CmdBeginRenderingKHR: std.meta.Child(c.PFN_vkCmdBeginRenderingKHR) = undefined,
    CmdEndRenderingKHR: std.meta.Child(c.PFN_vkCmdEndRenderingKHR) = undefined,
};
const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,
    transfer_family: ?u32 = null,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphics_family != null and
            self.present_family != null and
            self.transfer_family != null;
    }
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

pub var physical_device: c.VkPhysicalDevice = null;
pub var handle: c.VkDevice = null;
pub var dispatch: Dispatch = undefined;
pub var queue_family_indices: QueueFamilyIndices = undefined;
pub var features: c.VkPhysicalDeviceFeatures2 = undefined;
pub var properties: c.VkPhysicalDeviceProperties = undefined;

// *********************************************************************************************
// SwapChainSupportDetails
// *********************************************************************************************

pub const SwapChainSupportDetails = struct {
    allocator: std.mem.Allocator,
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    pub fn init(
        allocator: std.mem.Allocator,
        phys_device: c.VkPhysicalDevice,
        surface: c.VkSurfaceKHR,
    ) !SwapChainSupportDetails {
        var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
        try vk.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            phys_device,
            surface,
            &capabilities,
        );

        const formats = try vk.instance.getPhysicalDeviceSurfaceFormatsKHRAlloc(
            allocator,
            phys_device,
            surface,
        );
        errdefer allocator.free(formats);

        const present_modes = try vk.instance.getPhysicalDeviceSurfacePresentModesKHRAlloc(
            allocator,
            phys_device,
            surface,
        );
        errdefer allocator.free(present_modes);

        return .{
            .allocator = allocator,
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }

    pub fn deinit(self: *const SwapChainSupportDetails) void {
        self.allocator.free(self.formats);
        self.allocator.free(self.present_modes);
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn rateDeviceSuitability(
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    device: c.VkPhysicalDevice,
    required_extensions: []const [*:0]const u8,
) !u32 {
    std.debug.assert(device != null);

    var queue_family_properties = std.ArrayList(
        c.VkQueueFamilyProperties,
    ).init(
        allocator,
    );
    defer queue_family_properties.deinit();

    var score: u32 = 0;

    // Device properties
    var device_properties = std.mem.zeroes(
        c.VkPhysicalDeviceProperties,
    );
    vk.instance.getPhysicalDeviceProperties(
        device,
        &device_properties,
    );
    if (device_properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        score += 1000;
    }
    score += device_properties.limits.maxImageDimension2D;

    // Queue families
    const device_queue_family_indices = try findQueueFamilies(
        allocator,
        surface,
        device,
    );

    // Device features
    var physical_device_features = std.mem.zeroInit(
        c.VkPhysicalDeviceFeatures2,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        },
    );

    vk.instance.getPhysicalDeviceFeatures2(
        device,
        &physical_device_features,
    );

    const device_extension_support = try checkDeviceExtensionSupport(
        allocator,
        device,
        required_extensions,
    );

    var swap_chain_support = try SwapChainSupportDetails.init(
        allocator,
        device,
        surface,
    );
    defer swap_chain_support.deinit();

    const swap_chain_adequate = (swap_chain_support.formats.len > 0 and
        swap_chain_support.present_modes.len > 0);

    if (physical_device_features.features.geometryShader == 0 or
        !device_queue_family_indices.isComplete() or
        !device_extension_support or
        !swap_chain_adequate)
    {
        return 0;
    }

    return score;
}

fn findQueueFamilies(
    allocator: std.mem.Allocator,
    surface: c.VkSurfaceKHR,
    device: c.VkPhysicalDevice,
) !QueueFamilyIndices {
    std.debug.assert(device != null);

    var device_queue_family_indices = QueueFamilyIndices{};

    const queue_families = try vk.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
        allocator,
        device,
    );
    defer allocator.free(queue_families);

    for (queue_families, 0..) |queue_family, index| {
        if (device_queue_family_indices.graphics_family == null) {
            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                device_queue_family_indices.graphics_family = @intCast(index);
            }
        }

        if (device_queue_family_indices.transfer_family == null) {
            if (queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0 and
                queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == 0 and
                queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT == 0)
            {
                device_queue_family_indices.transfer_family = @intCast(index);
            }
        }

        if (device_queue_family_indices.present_family == null) {
            var present_support: c.VkBool32 = 0;
            try vk.instance.getPhysicalDeviceSurfaceSupportKHR(
                device,
                @intCast(index),
                surface,
                &present_support,
            );
            if (present_support != 0) {
                device_queue_family_indices.present_family = @intCast(index);
            }
        }

        if (device_queue_family_indices.isComplete()) {
            break;
        }
    }

    if (device_queue_family_indices.transfer_family == null) {
        device_queue_family_indices.transfer_family = device_queue_family_indices.graphics_family;
    }

    return device_queue_family_indices;
}

fn checkDeviceExtensionSupport(
    allocator: std.mem.Allocator,
    device: c.VkPhysicalDevice,
    required_extensions: []const [*:0]const u8,
) !bool {
    std.debug.assert(device != null);

    const available_extensions = try vk.instance.enumerateDeviceExtensionPropertiesAlloc(
        allocator,
        device,
        null,
    );
    defer allocator.free(available_extensions);

    for (required_extensions) |required_extension| {
        var found = false;
        for (available_extensions) |available_extension| {
            if (std.mem.eql(
                u8,
                std.mem.sliceTo(required_extension, 0),
                std.mem.sliceTo(&available_extension.extensionName, 0),
            )) {
                found = true;
                break;
            }
        }
        if (!found) {
            vk.log.err(
                "Required device extension not found: {s}",
                .{required_extension},
            );
            return false;
        }
    }

    return true;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(
    options: *const gfx.Options,
    surface: c.VkSurfaceKHR,
) !void {
    dispatch = try vk.library.load(Dispatch, vk.instance.handle);

    const physical_devices = try vk.instance.enumeratePhysicalDevicesAlloc(vk.arena);
    if (physical_devices.len == 0) {
        vk.log.err("No Vulkan physical devices found", .{});
        return error.NoPhysicalDevicesFound;
    }

    const device_required_extensions = [_][*:0]const u8{
        c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        c.VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,
        c.VK_KHR_DYNAMIC_RENDERING_EXTENSION_NAME,
    };

    var selected_physical_device: c.VkPhysicalDevice = null;
    var selected_physical_device_score: u32 = 0;
    var selected_physical_device_index: usize = 0;
    var selected_physical_device_properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
    for (physical_devices, 0..) |current_physical_device, index| {
        const score = try rateDeviceSuitability(
            vk.arena,
            surface,
            current_physical_device,
            &device_required_extensions,
        );

        var current_properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
        vk.instance.getPhysicalDeviceProperties(current_physical_device, &current_properties);

        vk.log.debug("Physical device {s} ({d}):", .{ current_properties.deviceName, index });
        vk.log.debug("  - API version: {d}.{d}.{d}", .{
            c.VK_API_VERSION_MAJOR(current_properties.apiVersion),
            c.VK_API_VERSION_MINOR(current_properties.apiVersion),
            c.VK_API_VERSION_PATCH(current_properties.apiVersion),
        });
        vk.log.debug("  - API variant: {d}", .{
            c.VK_API_VERSION_VARIANT(current_properties.apiVersion),
        });
        vk.log.debug("  - Driver version: {x}", .{current_properties.driverVersion});
        vk.log.debug("  - Vendor ID: {x}", .{current_properties.vendorID});
        vk.log.debug("  - Device ID: {x}", .{current_properties.deviceID});
        vk.log.debug("  - Type: {s}", .{c.string_VkPhysicalDeviceType(current_properties.deviceType)});
        vk.log.debug("  - Score: {d}", .{score});

        var memory_properties = std.mem.zeroes(
            c.VkPhysicalDeviceMemoryProperties,
        );
        vk.instance.getPhysicalDeviceMemoryProperties(
            current_physical_device,
            &memory_properties,
        );

        vk.log.debug("  - Memory type count: {d}", .{memory_properties.memoryTypeCount});
        for (0..memory_properties.memoryTypeCount) |mp_index| {
            const memory_type = memory_properties.memoryTypes[mp_index];
            vk.log.debug(
                "    {d:0>3}: flags 0x{x:0>8}, index {d}",
                .{ mp_index, memory_type.propertyFlags, memory_type.heapIndex },
            );
        }
        vk.log.debug("  - Memory heap count: {d}", .{memory_properties.memoryHeapCount});
        for (0..memory_properties.memoryHeapCount) |mh_index| {
            const memory_heap = memory_properties.memoryHeaps[mh_index];
            vk.log.debug(
                "    {d:0>3}: size {d}, flags 0x{x:0>8}",
                .{ mh_index, std.fmt.fmtIntSizeDec(memory_heap.size), memory_heap.flags },
            );
        }

        if (selected_physical_device == null or score > selected_physical_device_score) {
            selected_physical_device = current_physical_device;
            selected_physical_device_score = score;
            selected_physical_device_index = index;
            selected_physical_device_properties = current_properties;
        }
    }

    if (selected_physical_device == null) {
        vk.log.err("No suitable Vulkan physical devices found", .{});
        return error.NoSuitablePhysicalDevicesFound;
    }

    queue_family_indices = try findQueueFamilies(
        vk.gpa,
        surface,
        selected_physical_device,
    );

    var unique_queue_families = std.AutoHashMap(u32, void).init(vk.arena);
    try unique_queue_families.put(queue_family_indices.graphics_family.?, void{});
    try unique_queue_families.put(queue_family_indices.present_family.?, void{});
    try unique_queue_families.put(queue_family_indices.transfer_family.?, void{});

    vk.log.debug("Using physical device {s} ({d}):", .{
        selected_physical_device_properties.deviceName,
        selected_physical_device_index,
    });
    vk.log.debug("  - Graphics queue family: {d}", .{queue_family_indices.graphics_family.?});
    vk.log.debug("  - Present queue family: {d}", .{queue_family_indices.present_family.?});
    vk.log.debug("  - Transer queue family: {d}", .{queue_family_indices.transfer_family.?});

    var device_queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(vk.arena);
    const queue_priorities = [_]f32{1.0};
    var unique_queue_iterator = unique_queue_families.keyIterator();
    while (unique_queue_iterator.next()) |queue_family| {
        const device_queue_create_info = std.mem.zeroInit(
            c.VkDeviceQueueCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .queueFamilyIndex = queue_family.*,
                .queueCount = queue_priorities.len,
                .pQueuePriorities = &queue_priorities,
            },
        );
        try device_queue_create_infos.append(device_queue_create_info);
    }
    var dynamic_rendering_features = std.mem.zeroInit(
        c.VkPhysicalDeviceDynamicRenderingFeaturesKHR,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
            .dynamicRendering = c.VK_TRUE,
        },
    );

    var physical_device_features = std.mem.zeroInit(
        c.VkPhysicalDeviceFeatures2,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        },
    );
    vk.instance.getPhysicalDeviceFeatures2(selected_physical_device, &physical_device_features);

    const validation_layers = try vk.prepareValidationLayers(vk.arena, options);

    const device_create_info = std.mem.zeroInit(
        c.VkDeviceCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = &dynamic_rendering_features,
            .queueCreateInfoCount = @as(u32, @intCast(device_queue_create_infos.items.len)),
            .pQueueCreateInfos = device_queue_create_infos.items.ptr,
            .enabledLayerCount = @as(u32, @intCast(validation_layers.items.len)),
            .ppEnabledLayerNames = validation_layers.items.ptr,
            .enabledExtensionCount = @as(u32, @intCast(device_required_extensions.len)),
            .ppEnabledExtensionNames = &device_required_extensions,
            .pEnabledFeatures = &physical_device_features.features,
        },
    );

    try vk.instance.createDevice(
        selected_physical_device,
        &device_create_info,
        &handle,
    );
    errdefer dispatch.DestroyDevice(handle, vk.instance.allocation_callbacks);

    physical_device = selected_physical_device;
    features = physical_device_features;
    properties = selected_physical_device_properties;
}

pub fn deinit() void {
    dispatch.DestroyDevice(
        handle,
        vk.instance.allocation_callbacks,
    );
}

pub fn acquireNextImageKHR(
    swapchain: c.VkSwapchainKHR,
    timeout: u64,
    semaphore: c.VkSemaphore,
    fence: c.VkFence,
    image_index: *u32,
) !c.VkResult {
    std.debug.assert(swapchain != null);

    const result = dispatch.AcquireNextImageKHR(
        handle,
        swapchain,
        timeout,
        semaphore,
        fence,
        image_index,
    );

    // Not an error, but should be handled by the caller.
    if (result == c.VK_SUBOPTIMAL_KHR or result == c.VK_ERROR_OUT_OF_DATE_KHR) {
        return result;
    }

    try vk.checkVulkanError(
        "Failed to acquire next Vulkan image",
        result,
    );

    return result;
}

pub inline fn allocateCommandBuffers(
    allocate_info: *const c.VkCommandBufferAllocateInfo,
    command_buffers: [*c]c.VkCommandBuffer,
) !void {
    try vk.checkVulkanError(
        "Failed to allocate Vulkan command buffers",
        dispatch.AllocateCommandBuffers(
            handle,
            allocate_info,
            command_buffers,
        ),
    );
}

pub inline fn allocateDescriptorSets(
    allocate_info: *const c.VkDescriptorSetAllocateInfo,
    descriptor_sets: [*c]c.VkDescriptorSet,
) !void {
    try vk.checkVulkanError(
        "Failed to allocate Vulkan descriptor sets",
        dispatch.AllocateDescriptorSets(
            handle,
            allocate_info,
            descriptor_sets,
        ),
    );
}

pub inline fn allocateMemory(
    allocate_info: *const c.VkMemoryAllocateInfo,
    memory: *c.VkDeviceMemory,
) !void {
    try vk.checkVulkanError(
        "Failed to allocate Vulkan memory",
        dispatch.AllocateMemory(
            handle,
            allocate_info,
            vk.instance.allocation_callbacks,
            memory,
        ),
    );
}

pub inline fn beginCommandBuffer(
    command_buffer: c.VkCommandBuffer,
    begin_info: *const c.VkCommandBufferBeginInfo,
) !void {
    std.debug.assert(command_buffer != null);

    try vk.checkVulkanError(
        "Failed to begin Vulkan command buffer",
        dispatch.BeginCommandBuffer(
            command_buffer,
            begin_info,
        ),
    );
}

pub inline fn bindBufferMemory(
    buffer: c.VkBuffer,
    memory: c.VkDeviceMemory,
    offset: c.VkDeviceSize,
) !void {
    std.debug.assert(buffer != null);
    std.debug.assert(memory != null);

    try vk.checkVulkanError(
        "Failed to bind Vulkan buffer memory",
        dispatch.BindBufferMemory(
            handle,
            buffer,
            memory,
            offset,
        ),
    );
}

pub inline fn bindImageMemory(
    image: c.VkImage,
    memory: c.VkDeviceMemory,
    offset: c.VkDeviceSize,
) !void {
    std.debug.assert(image != null);
    std.debug.assert(memory != null);

    try vk.checkVulkanError(
        "Failed to bind Vulkan image memory",
        dispatch.BindImageMemory(
            handle,
            image,
            memory,
            offset,
        ),
    );
}

pub inline fn cmdBindDescriptorSets(
    command_buffer: c.VkCommandBuffer,
    pipeline_bind_point: c.VkPipelineBindPoint,
    layout: c.VkPipelineLayout,
    first_set: u32,
    descriptor_set_count: u32,
    descriptor_sets: [*c]const c.VkDescriptorSet,
    dynamic_offset_count: u32,
    dynamic_offsets: [*c]const u32,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(layout != null);

    dispatch.CmdBindDescriptorSets(
        command_buffer,
        pipeline_bind_point,
        layout,
        first_set,
        descriptor_set_count,
        descriptor_sets,
        dynamic_offset_count,
        dynamic_offsets,
    );
}

pub inline fn cmdBindIndexBuffer(
    command_buffer: c.VkCommandBuffer,
    buffer: c.VkBuffer,
    offset: c.VkDeviceSize,
    index_type: c.VkIndexType,
) void {
    std.debug.assert(command_buffer != null);

    dispatch.CmdBindIndexBuffer(
        command_buffer,
        buffer,
        offset,
        index_type,
    );
}

pub inline fn cmdBindPipeline(
    command_buffer: c.VkCommandBuffer,
    pipeline_bind_point: c.VkPipelineBindPoint,
    pipeline: c.VkPipeline,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(pipeline != null);

    dispatch.CmdBindPipeline(
        command_buffer,
        pipeline_bind_point,
        pipeline,
    );
}

pub inline fn cmdBindVertexBuffers(
    command_buffer: c.VkCommandBuffer,
    first_binding: u32,
    binding_count: u32,
    buffers: [*c]const c.VkBuffer,
    offsets: [*c]c.VkDeviceSize,
) void {
    std.debug.assert(command_buffer != null);

    dispatch.CmdBindVertexBuffers(
        command_buffer,
        first_binding,
        binding_count,
        buffers,
        offsets,
    );
}

pub inline fn cmdBlitImage(
    command_buffer: c.VkCommandBuffer,
    src_image: c.VkImage,
    src_image_layout: c.VkImageLayout,
    dst_image: c.VkImage,
    dst_image_layout: c.VkImageLayout,
    region_count: u32,
    regions: [*c]const c.VkImageBlit,
    filter: c.VkFilter,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(src_image != null);
    std.debug.assert(dst_image != null);

    dispatch.CmdBlitImage(
        command_buffer,
        src_image,
        src_image_layout,
        dst_image,
        dst_image_layout,
        region_count,
        regions,
        filter,
    );
}

pub inline fn cmdCopyBuffer(
    command_buffer: c.VkCommandBuffer,
    src_buffer: c.VkBuffer,
    dst_buffer: c.VkBuffer,
    region_count: u32,
    regions: [*c]const c.VkBufferCopy,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(src_buffer != null);
    std.debug.assert(dst_buffer != null);

    dispatch.CmdCopyBuffer(
        command_buffer,
        src_buffer,
        dst_buffer,
        region_count,
        regions,
    );
}

pub inline fn cmdCopyBufferToImage(
    command_buffer: c.VkCommandBuffer,
    src_buffer: c.VkBuffer,
    dst_image: c.VkImage,
    dst_image_layout: c.VkImageLayout,
    region_count: u32,
    regions: [*c]const c.VkBufferImageCopy,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(src_buffer != null);
    std.debug.assert(dst_image != null);

    dispatch.CmdCopyBufferToImage(
        command_buffer,
        src_buffer,
        dst_image,
        dst_image_layout,
        region_count,
        regions,
    );
}

pub inline fn cmdDraw(
    command_buffer: c.VkCommandBuffer,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    std.debug.assert(command_buffer != null);

    dispatch.CmdDraw(
        command_buffer,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub inline fn cmdDrawIndexed(
    command_buffer: c.VkCommandBuffer,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    std.debug.assert(command_buffer != null);

    dispatch.CmdDrawIndexed(
        command_buffer,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}

pub inline fn cmdPipelineBarrier(
    command_buffer: c.VkCommandBuffer,
    src_stage_mask: c.VkPipelineStageFlags,
    dst_stage_mask: c.VkPipelineStageFlags,
    dependency_flags: c.VkDependencyFlags,
    memory_barrier_count: u32,
    memory_barriers: [*c]const c.VkMemoryBarrier,
    buffer_memory_barrier_count: u32,
    buffer_memory_barriers: [*c]const c.VkBufferMemoryBarrier,
    image_memory_barrier_count: u32,
    image_memory_barriers: [*c]const c.VkImageMemoryBarrier,
) void {
    std.debug.assert(command_buffer != null);
    dispatch.CmdPipelineBarrier(
        command_buffer,
        src_stage_mask,
        dst_stage_mask,
        dependency_flags,
        memory_barrier_count,
        memory_barriers,
        buffer_memory_barrier_count,
        buffer_memory_barriers,
        image_memory_barrier_count,
        image_memory_barriers,
    );
}

pub inline fn cmdPushDescriptorSet(
    command_buffer: c.VkCommandBuffer,
    pipeline_bind_point: c.VkPipelineBindPoint,
    layout: c.VkPipelineLayout,
    set: u32,
    descriptor_write_count: u32,
    descriptor_writes: [*c]const c.VkWriteDescriptorSet,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(layout != null);

    dispatch.CmdPushDescriptorSetKHR(
        command_buffer,
        pipeline_bind_point,
        layout,
        set,
        descriptor_write_count,
        descriptor_writes,
    );
}

pub inline fn cmdPushConstants(
    command_buffer: c.VkCommandBuffer,
    layout: c.VkPipelineLayout,
    stage_flags: c.VkShaderStageFlags,
    offset: u32,
    size: u32,
    values: [*c]const u8,
) void {
    std.debug.assert(command_buffer != null);
    std.debug.assert(layout != null);

    dispatch.CmdPushConstants(
        command_buffer,
        layout,
        stage_flags,
        offset,
        size,
        values,
    );
}

pub inline fn cmdSetScissor(
    command_buffer: c.VkCommandBuffer,
    first_scissor: u32,
    scissor_count: u32,
    scissors: [*c]const c.VkRect2D,
) void {
    std.debug.assert(command_buffer != null);
    dispatch.CmdSetScissor(
        command_buffer,
        first_scissor,
        scissor_count,
        scissors,
    );
}

pub inline fn cmdSetViewport(
    command_buffer: c.VkCommandBuffer,
    first_viewport: u32,
    viewport_count: u32,
    viewports: [*c]const c.VkViewport,
) void {
    std.debug.assert(command_buffer != null);
    dispatch.CmdSetViewport(
        command_buffer,
        first_viewport,
        viewport_count,
        viewports,
    );
}

pub inline fn createBuffer(
    create_info: *const c.VkBufferCreateInfo,
    buffer: *c.VkBuffer,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan buffer",
        dispatch.CreateBuffer(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            buffer,
        ),
    );
}

pub inline fn createCommandPool(
    create_info: *const c.VkCommandPoolCreateInfo,
    command_pool: *c.VkCommandPool,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan command pool",
        dispatch.CreateCommandPool(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            command_pool,
        ),
    );
}

pub inline fn createDescriptorPool(
    create_info: *const c.VkDescriptorPoolCreateInfo,
    descriptor_pool: *c.VkDescriptorPool,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan descriptor pool",
        dispatch.CreateDescriptorPool(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            descriptor_pool,
        ),
    );
}

pub inline fn createDescriptorSetLayout(
    create_info: *const c.VkDescriptorSetLayoutCreateInfo,
    descriptor_set_layout: *c.VkDescriptorSetLayout,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan descriptor set layout",
        dispatch.CreateDescriptorSetLayout(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            descriptor_set_layout,
        ),
    );
}

pub inline fn createFence(
    create_info: *const c.VkFenceCreateInfo,
    fence: *c.VkFence,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan fence",
        dispatch.CreateFence(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            fence,
        ),
    );
}

pub inline fn createFrameBuffer(
    create_info: *const c.VkFramebufferCreateInfo,
    frame_buffer: *c.VkFramebuffer,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan frame buffer",
        dispatch.CreateFramebuffer(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            frame_buffer,
        ),
    );
}

pub inline fn createGraphicsPipelines(
    pipeline_cache: c.VkPipelineCache,
    create_info_count: u32,
    create_infos: [*c]const c.VkGraphicsPipelineCreateInfo,
    pipelines: [*c]c.VkPipeline,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan graphics pipelines",
        dispatch.CreateGraphicsPipelines(
            handle,
            pipeline_cache,
            create_info_count,
            create_infos,
            vk.instance.allocation_callbacks,
            pipelines,
        ),
    );
}

pub inline fn createImage(
    create_info: *const c.VkImageCreateInfo,
    image: *c.VkImage,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan image",
        dispatch.CreateImage(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            image,
        ),
    );
}

pub inline fn createImageView(
    create_info: *const c.VkImageViewCreateInfo,
    image_view: *c.VkImageView,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan image view",
        dispatch.CreateImageView(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            image_view,
        ),
    );
}

pub inline fn createPipelineLayout(
    create_info: *const c.VkPipelineLayoutCreateInfo,
    pipeline_layout: *c.VkPipelineLayout,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan pipeline layout",
        dispatch.CreatePipelineLayout(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            pipeline_layout,
        ),
    );
}

pub inline fn createSampler(
    create_info: *const c.VkSamplerCreateInfo,
    sampler: *c.VkSampler,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan sampler",
        dispatch.CreateSampler(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            sampler,
        ),
    );
}

pub inline fn createSemaphore(
    create_info: *const c.VkSemaphoreCreateInfo,
    semaphore: *c.VkSemaphore,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan semaphore",
        dispatch.CreateSemaphore(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            semaphore,
        ),
    );
}

pub inline fn createShaderModule(
    create_info: *const c.VkShaderModuleCreateInfo,
    shader_module: *c.VkShaderModule,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan shader module",
        dispatch.CreateShaderModule(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            shader_module,
        ),
    );
}

pub inline fn createSwapchainKHR(
    create_info: *const c.VkSwapchainCreateInfoKHR,
    swapchain: *c.VkSwapchainKHR,
) !void {
    try vk.checkVulkanError(
        "Failed to create Vulkan swapchain",
        dispatch.CreateSwapchainKHR(
            handle,
            create_info,
            vk.instance.allocation_callbacks,
            swapchain,
        ),
    );
}

pub inline fn destroyBuffer(buffer: c.VkBuffer) void {
    std.debug.assert(buffer != null);
    dispatch.DestroyBuffer(
        handle,
        buffer,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyCommandPool(command_pool: c.VkCommandPool) void {
    std.debug.assert(command_pool != null);
    dispatch.DestroyCommandPool(
        handle,
        command_pool,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyDescriptorPool(descriptor_pool: c.VkDescriptorPool) void {
    std.debug.assert(descriptor_pool != null);
    dispatch.DestroyDescriptorPool(
        handle,
        descriptor_pool,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyDescriptorSetLayout(descriptor_set_layout: c.VkDescriptorSetLayout) void {
    std.debug.assert(descriptor_set_layout != null);
    dispatch.DestroyDescriptorSetLayout(
        handle,
        descriptor_set_layout,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyFence(fence: c.VkFence) void {
    std.debug.assert(fence != null);
    dispatch.DestroyFence(
        handle,
        fence,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyFrameBuffer(frame_buffer: c.VkFramebuffer) void {
    std.debug.assert(frame_buffer != null);
    dispatch.DestroyFramebuffer(
        handle,
        frame_buffer,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyImage(image: c.VkImage) void {
    std.debug.assert(image != null);
    dispatch.DestroyImage(
        handle,
        image,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyImageView(image_view: c.VkImageView) void {
    std.debug.assert(image_view != null);
    dispatch.DestroyImageView(
        handle,
        image_view,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyPipeline(pipeline: c.VkPipeline) void {
    std.debug.assert(pipeline != null);
    dispatch.DestroyPipeline(
        handle,
        pipeline,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyPipelineLayout(pipeline_layout: c.VkPipelineLayout) void {
    std.debug.assert(pipeline_layout != null);
    dispatch.DestroyPipelineLayout(
        handle,
        pipeline_layout,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroySampler(sampler: c.VkSampler) void {
    std.debug.assert(sampler != null);
    dispatch.DestroySampler(
        handle,
        sampler,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroySemaphore(semaphore: c.VkSemaphore) void {
    std.debug.assert(semaphore != null);
    dispatch.DestroySemaphore(
        handle,
        semaphore,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroyShaderModule(shader_module: c.VkShaderModule) void {
    std.debug.assert(shader_module != null);
    dispatch.DestroyShaderModule(
        handle,
        shader_module,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn destroySwapchainKHR(swapchain: c.VkSwapchainKHR) void {
    std.debug.assert(swapchain != null);
    dispatch.DestroySwapchainKHR(
        handle,
        swapchain,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn deviceWaitIdle() !void {
    try vk.checkVulkanError(
        "Failed to wait for Vulkan device idle",
        dispatch.DeviceWaitIdle(handle),
    );
}

pub inline fn endCommandBuffer(command_buffer: c.VkCommandBuffer) !void {
    std.debug.assert(command_buffer != null);
    try vk.checkVulkanError(
        "Failed to end Vulkan command buffer",
        dispatch.EndCommandBuffer(command_buffer),
    );
}

pub inline fn freeCommandBuffers(
    command_pool: c.VkCommandPool,
    command_buffer_count: u32,
    command_buffers: [*c]const c.VkCommandBuffer,
) void {
    std.debug.assert(command_pool != null);
    dispatch.FreeCommandBuffers(
        handle,
        command_pool,
        command_buffer_count,
        command_buffers,
    );
}

pub inline fn freeDescriptorSets(
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set_count: u32,
    descriptor_sets: [*c]c.VkDescriptorSet,
) !void {
    std.debug.assert(descriptor_pool != null);
    try vk.checkVulkanError(
        "Failed to free Vulkan descriptor sets",
        dispatch.FreeDescriptorSets(
            handle,
            descriptor_pool,
            descriptor_set_count,
            descriptor_sets,
        ),
    );
}

pub inline fn freeMemory(memory: c.VkDeviceMemory) void {
    std.debug.assert(memory != null);
    dispatch.FreeMemory(
        handle,
        memory,
        vk.instance.allocation_callbacks,
    );
}

pub inline fn getBufferMemoryRequirements(
    buffer: c.VkBuffer,
    requirements: *c.VkMemoryRequirements,
) void {
    std.debug.assert(buffer != null);
    dispatch.GetBufferMemoryRequirements(
        handle,
        buffer,
        requirements,
    );
}

pub inline fn getDeviceQueue(
    queue_family_index: u32,
    queue_index: u32,
    queue: *c.VkQueue,
) void {
    dispatch.GetDeviceQueue(
        handle,
        queue_family_index,
        queue_index,
        queue,
    );
}

pub inline fn getImageMemoryRequirements(
    image: c.VkImage,
    requirements: *c.VkMemoryRequirements,
) void {
    std.debug.assert(image != null);
    dispatch.GetImageMemoryRequirements(
        handle,
        image,
        requirements,
    );
}

pub inline fn getImageSubresourceLayout(
    image: c.VkImage,
    subresource: *c.VkImageSubresource,
    layout: *c.VkSubresourceLayout,
) void {
    std.debug.assert(image != null);
    dispatch.GetImageSubresourceLayout(
        handle,
        image,
        subresource,
        layout,
    );
}

pub inline fn getSwapchainImagesKHR(
    swapchain: c.VkSwapchainKHR,
    count: *u32,
    images: [*c]c.VkImage,
) !void {
    std.debug.assert(swapchain != null);
    try vk.checkVulkanError(
        "Failed to get swapchain images",
        dispatch.GetSwapchainImagesKHR(
            handle,
            swapchain,
            count,
            images,
        ),
    );
}

pub fn getSwapchainImagesKHRAlloc(
    allocator: std.mem.Allocator,
    swapchain: c.VkSwapchainKHR,
) ![]c.VkImage {
    std.debug.assert(swapchain != null);

    var count: u32 = undefined;
    try getSwapchainImagesKHR(
        swapchain,
        &count,
        null,
    );

    const result = try allocator.alloc(
        c.VkImage,
        count,
    );
    errdefer allocator.free(result);

    try getSwapchainImagesKHR(
        swapchain,
        &count,
        result.ptr,
    );
    return result;
}

pub inline fn mapMemory(
    memory: c.VkDeviceMemory,
    offset: c.VkDeviceSize,
    size: c.VkDeviceSize,
    flags: c.VkMemoryMapFlags,
    data: [*c]?*anyopaque,
) !void {
    std.debug.assert(memory != null);
    std.debug.assert(data != null);

    try vk.checkVulkanError(
        "Failed to map Vulkan memory",
        dispatch.MapMemory(
            handle,
            memory,
            offset,
            size,
            flags,
            data,
        ),
    );
}

pub inline fn queuePresentKHR(
    queue: c.VkQueue,
    present_info: *const c.VkPresentInfoKHR,
) !c.VkResult {
    std.debug.assert(queue != null);

    const result = dispatch.QueuePresentKHR(
        queue,
        present_info,
    );

    // Not error, but should be handled.
    if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) {
        return result;
    }

    try vk.checkVulkanError("Failed to present Vulkan queue", result);

    return result;
}

pub inline fn queueSubmit(
    queue: c.VkQueue,
    submit_count: u32,
    submits: [*c]const c.VkSubmitInfo,
    fence: c.VkFence,
) !void {
    std.debug.assert(queue != null);
    std.debug.assert(submits != null);

    try vk.checkVulkanError(
        "Failed to submit Vulkan queue",
        dispatch.QueueSubmit(
            queue,
            submit_count,
            submits,
            fence,
        ),
    );
}

pub inline fn queueWaitIdle(queue: c.VkQueue) !void {
    std.debug.assert(queue != null);
    try vk.checkVulkanError(
        "Failed to wait for Vulkan queue",
        dispatch.QueueWaitIdle(queue),
    );
}

pub inline fn resetCommandBuffer(
    command_buffer: c.VkCommandBuffer,
    flags: c.VkCommandBufferResetFlags,
) !void {
    std.debug.assert(command_buffer != null);
    try vk.checkVulkanError(
        "Failed to reset Vulkan command buffer",
        dispatch.ResetCommandBuffer(
            command_buffer,
            flags,
        ),
    );
}

pub inline fn resetFences(
    fence_count: u32,
    fences: [*c]c.VkFence,
) !void {
    try vk.checkVulkanError(
        "Failed to reset Vulkan fences",
        dispatch.ResetFences(
            handle,
            fence_count,
            fences,
        ),
    );
}

pub inline fn unmapMemory(memory: c.VkDeviceMemory) void {
    std.debug.assert(memory != null);
    dispatch.UnmapMemory(
        handle,
        memory,
    );
}

pub inline fn updateDescriptorSets(
    descriptor_write_count: u32,
    descriptor_writes: [*c]const c.VkWriteDescriptorSet,
    descriptor_copy_count: u32,
    descriptor_copies: [*c]const c.VkCopyDescriptorSet,
) void {
    dispatch.UpdateDescriptorSets(
        handle,
        descriptor_write_count,
        descriptor_writes,
        descriptor_copy_count,
        descriptor_copies,
    );
}

pub inline fn waitForFences(
    fence_count: u32,
    fences: [*c]c.VkFence,
    wait_all: c.VkBool32,
    timeout: u64,
) !void {
    try vk.checkVulkanError(
        "Failed to wait for Vulkan fences",
        dispatch.WaitForFences(
            handle,
            fence_count,
            fences,
            wait_all,
            timeout,
        ),
    );
}

pub inline fn cmdBeginRenderingKHR(
    command_buffer: c.VkCommandBuffer,
    rendering_info: *const c.VkRenderingInfo,
) void {
    dispatch.CmdBeginRenderingKHR(command_buffer, rendering_info);
}

pub inline fn cmdEndRenderingKHR(
    command_buffer: c.VkCommandBuffer,
) void {
    dispatch.CmdEndRenderingKHR(command_buffer);
}
