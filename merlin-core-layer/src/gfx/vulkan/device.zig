const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Device = struct {
    const Self = @This();
    const Dispatch = struct {
        AcquireNextImageKHR: std.meta.Child(c.PFN_vkAcquireNextImageKHR) = undefined,
        AllocateCommandBuffers: std.meta.Child(c.PFN_vkAllocateCommandBuffers) = undefined,
        AllocateDescriptorSets: std.meta.Child(c.PFN_vkAllocateDescriptorSets) = undefined,
        AllocateMemory: std.meta.Child(c.PFN_vkAllocateMemory) = undefined,
        BeginCommandBuffer: std.meta.Child(c.PFN_vkBeginCommandBuffer) = undefined,
        BindBufferMemory: std.meta.Child(c.PFN_vkBindBufferMemory) = undefined,
        BindImageMemory: std.meta.Child(c.PFN_vkBindImageMemory) = undefined,
        CmdBeginRenderPass: std.meta.Child(c.PFN_vkCmdBeginRenderPass) = undefined,
        CmdBindDescriptorSets: std.meta.Child(c.PFN_vkCmdBindDescriptorSets) = undefined,
        CmdBindIndexBuffer: std.meta.Child(c.PFN_vkCmdBindIndexBuffer) = undefined,
        CmdBindPipeline: std.meta.Child(c.PFN_vkCmdBindPipeline) = undefined,
        CmdBindVertexBuffers: std.meta.Child(c.PFN_vkCmdBindVertexBuffers) = undefined,
        CmdBlitImage: std.meta.Child(c.PFN_vkCmdBlitImage) = undefined,
        CmdCopyBuffer: std.meta.Child(c.PFN_vkCmdCopyBuffer) = undefined,
        CmdCopyBufferToImage: std.meta.Child(c.PFN_vkCmdCopyBufferToImage) = undefined,
        CmdDraw: std.meta.Child(c.PFN_vkCmdDraw) = undefined,
        CmdDrawIndexed: std.meta.Child(c.PFN_vkCmdDrawIndexed) = undefined,
        CmdEndRenderPass: std.meta.Child(c.PFN_vkCmdEndRenderPass) = undefined,
        CmdPipelineBarrier: std.meta.Child(c.PFN_vkCmdPipelineBarrier) = undefined,
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
        CreateRenderPass: std.meta.Child(c.PFN_vkCreateRenderPass) = undefined,
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
        DestroyRenderPass: std.meta.Child(c.PFN_vkDestroyRenderPass) = undefined,
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
        GetPhysicalDeviceFeatures2: std.meta.Child(c.PFN_vkGetPhysicalDeviceFeatures2) = undefined,
        GetPhysicalDeviceFormatProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceFormatProperties) = undefined,
        GetPhysicalDeviceImageFormatProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceImageFormatProperties) = undefined,
        GetPhysicalDeviceMemoryProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceMemoryProperties) = undefined,
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

    instance: *const vk.Instance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    dispatch: Dispatch,
    queue_family_indices: QueueFamilyIndices,
    features: c.VkPhysicalDeviceFeatures2,
    ktx_vulkan_functions: c.struct_ktxVulkanFunctions,

    pub fn init(
        allocator: std.mem.Allocator,
        options: *const gfx.Options,
        library: *vk.Library,
        instance: *vk.Instance,
        surface: *const vk.Surface,
    ) !Self {
        const dispatch = try library.load(Dispatch, instance.handle);

        const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(physical_devices);

        if (physical_devices.len == 0) {
            vk.log.err("No Vulkan physical devices found", .{});
            return error.NoPhysicalDevicesFound;
        }

        const device_required_extensions = [_][*:0]const u8{
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
            c.VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,
        };

        var selected_physical_device: c.VkPhysicalDevice = null;
        var selected_physical_device_score: u32 = 0;
        var selected_physical_device_index: usize = 0;
        var selected_physical_device_properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
        for (physical_devices, 0..) |physical_device, index| {
            const score = try rateDeviceSuitability(
                allocator,
                instance,
                surface,
                physical_device,
                &device_required_extensions,
            );

            var properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
            instance.getPhysicalDeviceProperties(physical_device, &properties);

            vk.log.debug("Physical device {s} ({d}):", .{ properties.deviceName, index });
            vk.log.debug("  - API version: {d}.{d}.{d}", .{
                c.VK_API_VERSION_MAJOR(properties.apiVersion),
                c.VK_API_VERSION_MINOR(properties.apiVersion),
                c.VK_API_VERSION_PATCH(properties.apiVersion),
            });
            vk.log.debug("  - API variant: {d}", .{
                c.VK_API_VERSION_VARIANT(properties.apiVersion),
            });
            vk.log.debug("  - Driver version: {x}", .{properties.driverVersion});
            vk.log.debug("  - Vendor ID: {x}", .{properties.vendorID});
            vk.log.debug("  - Device ID: {x}", .{properties.deviceID});
            vk.log.debug("  - Type: {s}", .{c.string_VkPhysicalDeviceType(properties.deviceType)});
            vk.log.debug("  - Score: {d}", .{score});

            var memory_properties = std.mem.zeroes(
                c.VkPhysicalDeviceMemoryProperties,
            );
            instance.getPhysicalDeviceMemoryProperties(
                physical_device,
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
                    .{ mh_index, std.fmt.fmtIntSizeBin(memory_heap.size), memory_heap.flags },
                );
            }

            if (selected_physical_device == null or score > selected_physical_device_score) {
                selected_physical_device = physical_device;
                selected_physical_device_score = score;
                selected_physical_device_index = index;
                selected_physical_device_properties = properties;
            }
        }

        if (selected_physical_device == null) {
            vk.log.err("No suitable Vulkan physical devices found", .{});
            return error.NoSuitablePhysicalDevicesFound;
        }

        const queue_family_indices = try findQueueFamilies(
            allocator,
            instance,
            surface,
            selected_physical_device,
        );

        var unique_queue_families = std.AutoHashMap(u32, void).init(allocator);
        defer unique_queue_families.deinit();
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

        var device_queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(allocator);
        defer device_queue_create_infos.deinit();

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
        var physical_device_features = std.mem.zeroInit(
            c.VkPhysicalDeviceFeatures2,
            .{
                .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
            },
        );
        dispatch.GetPhysicalDeviceFeatures2(selected_physical_device, &physical_device_features);

        const validation_layers = try vk.prepareValidationLayers(
            allocator,
            options,
        );
        defer validation_layers.deinit();

        const device_create_info = std.mem.zeroInit(
            c.VkDeviceCreateInfo,
            .{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                .queueCreateInfoCount = @as(u32, @intCast(device_queue_create_infos.items.len)),
                .pQueueCreateInfos = device_queue_create_infos.items.ptr,
                .enabledLayerCount = @as(u32, @intCast(validation_layers.items.len)),
                .ppEnabledLayerNames = validation_layers.items.ptr,
                .enabledExtensionCount = @as(u32, @intCast(device_required_extensions.len)),
                .ppEnabledExtensionNames = &device_required_extensions,
                .pEnabledFeatures = &physical_device_features.features,
            },
        );

        var device: c.VkDevice = undefined;
        try instance.createDevice(
            selected_physical_device,
            &device_create_info,
            &device,
        );
        errdefer dispatch.DestroyDevice(device, instance.allocation_callbacks);

        const ktx_vulkan_functions = c.struct_ktxVulkanFunctions{
            .vkGetInstanceProcAddr = library.get_instance_proc_addr,
            .vkGetDeviceProcAddr = library.get_device_proc_addr,
            .vkAllocateCommandBuffers = dispatch.AllocateCommandBuffers,
            .vkAllocateMemory = dispatch.AllocateMemory,
            .vkBeginCommandBuffer = dispatch.BeginCommandBuffer,
            .vkBindBufferMemory = dispatch.BindBufferMemory,
            .vkBindImageMemory = dispatch.BindImageMemory,
            .vkCmdBlitImage = dispatch.CmdBlitImage,
            .vkCmdCopyBufferToImage = dispatch.CmdCopyBufferToImage,
            .vkCmdPipelineBarrier = dispatch.CmdPipelineBarrier,
            .vkCreateImage = dispatch.CreateImage,
            .vkDestroyImage = dispatch.DestroyImage,
            .vkCreateBuffer = dispatch.CreateBuffer,
            .vkDestroyBuffer = dispatch.DestroyBuffer,
            .vkCreateFence = dispatch.CreateFence,
            .vkDestroyFence = dispatch.DestroyFence,
            .vkEndCommandBuffer = dispatch.EndCommandBuffer,
            .vkFreeCommandBuffers = dispatch.FreeCommandBuffers,
            .vkFreeMemory = dispatch.FreeMemory,
            .vkGetBufferMemoryRequirements = dispatch.GetBufferMemoryRequirements,
            .vkGetImageMemoryRequirements = dispatch.GetImageMemoryRequirements,
            .vkGetImageSubresourceLayout = dispatch.GetImageSubresourceLayout,
            .vkGetPhysicalDeviceImageFormatProperties = dispatch.GetPhysicalDeviceImageFormatProperties,
            .vkGetPhysicalDeviceFormatProperties = dispatch.GetPhysicalDeviceFormatProperties,
            .vkGetPhysicalDeviceMemoryProperties = dispatch.GetPhysicalDeviceMemoryProperties,
            .vkMapMemory = dispatch.MapMemory,
            .vkQueueSubmit = dispatch.QueueSubmit,
            .vkQueueWaitIdle = dispatch.QueueWaitIdle,
            .vkUnmapMemory = dispatch.UnmapMemory,
            .vkWaitForFences = dispatch.WaitForFences,
        };

        return .{
            .instance = instance,
            .physical_device = selected_physical_device,
            .device = device,
            .dispatch = dispatch,
            .queue_family_indices = queue_family_indices,
            .features = physical_device_features,
            .ktx_vulkan_functions = ktx_vulkan_functions,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dispatch.DestroyDevice(
            self.device,
            self.instance.allocation_callbacks,
        );
    }

    fn rateDeviceSuitability(
        allocator: std.mem.Allocator,
        instance: *vk.Instance,
        surface: *const vk.Surface,
        physical_device: c.VkPhysicalDevice,
        required_extensions: []const [*:0]const u8,
    ) !u32 {
        std.debug.assert(physical_device != null);

        var properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
        var features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
        var queue_family_properties = std.ArrayList(c.VkQueueFamilyProperties).init(
            allocator,
        );
        defer queue_family_properties.deinit();

        var score: u32 = 0;

        // Device properties
        instance.getPhysicalDeviceProperties(
            physical_device,
            &properties,
        );
        if (properties.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            score += 1000;
        }
        score += properties.limits.maxImageDimension2D;

        // Queue families
        const queue_family_indices = try findQueueFamilies(
            allocator,
            instance,
            surface,
            physical_device,
        );

        // Device features
        instance.getPhysicalDeviceFeatures(
            physical_device,
            &features,
        );

        const device_extension_support = try checkDeviceExtensionSupport(
            allocator,
            instance,
            physical_device,
            required_extensions,
        );

        var swap_chain_support = try vk.SwapChainSupportDetails.init(
            allocator,
            instance,
            physical_device,
            surface.handle,
        );
        defer swap_chain_support.deinit();

        const swap_chain_adequate = (swap_chain_support.formats.len > 0 and
            swap_chain_support.present_modes.len > 0);

        if (features.geometryShader == 0 or
            !queue_family_indices.isComplete() or
            !device_extension_support or
            !swap_chain_adequate)
        {
            return 0;
        }

        return score;
    }

    fn findQueueFamilies(
        allocator: std.mem.Allocator,
        instance: *vk.Instance,
        surface: *const vk.Surface,
        physical_device: c.VkPhysicalDevice,
    ) !QueueFamilyIndices {
        std.debug.assert(physical_device != null);

        var queue_family_indices = QueueFamilyIndices{};

        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
            allocator,
            physical_device,
        );
        defer allocator.free(queue_families);

        for (queue_families, 0..) |queue_family, index| {
            if (queue_family_indices.graphics_family == null) {
                if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                    queue_family_indices.graphics_family = @intCast(index);
                }
            }

            if (queue_family_indices.transfer_family == null) {
                if (queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT != 0 and
                    queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == 0 and
                    queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT == 0)
                {
                    queue_family_indices.transfer_family = @intCast(index);
                }
            }

            if (queue_family_indices.present_family == null) {
                var present_support: c.VkBool32 = 0;
                try instance.getPhysicalDeviceSurfaceSupportKHR(
                    physical_device,
                    @intCast(index),
                    surface.handle,
                    &present_support,
                );
                if (present_support != 0) {
                    queue_family_indices.present_family = @intCast(index);
                }
            }

            if (queue_family_indices.isComplete()) {
                break;
            }
        }

        if (queue_family_indices.transfer_family == null) {
            queue_family_indices.transfer_family = queue_family_indices.graphics_family;
        }

        return queue_family_indices;
    }

    fn checkDeviceExtensionSupport(
        allocator: std.mem.Allocator,
        instance: *vk.Instance,
        physical_device: c.VkPhysicalDevice,
        required_extensions: []const [*:0]const u8,
    ) !bool {
        std.debug.assert(physical_device != null);

        const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(
            allocator,
            physical_device,
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
    // Dispatch functions
    // *********************************************************************************************

    pub fn acquireNextImageKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
        timeout: u64,
        semaphore: c.VkSemaphore,
        fence: c.VkFence,
        image_index: *u32,
    ) !c.VkResult {
        std.debug.assert(swapchain != null);

        const result = self.dispatch.AcquireNextImageKHR(
            self.device,
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

    pub fn allocateCommandBuffers(
        self: *const Self,
        allocate_info: *const c.VkCommandBufferAllocateInfo,
        command_buffers: [*c]c.VkCommandBuffer,
    ) !void {
        try vk.checkVulkanError(
            "Failed to allocate Vulkan command buffers",
            self.dispatch.AllocateCommandBuffers(
                self.device,
                allocate_info,
                command_buffers,
            ),
        );
    }

    pub fn allocateDescriptorSets(
        self: *const Self,
        allocate_info: *const c.VkDescriptorSetAllocateInfo,
        descriptor_sets: [*c]c.VkDescriptorSet,
    ) !void {
        try vk.checkVulkanError(
            "Failed to allocate Vulkan descriptor sets",
            self.dispatch.AllocateDescriptorSets(
                self.device,
                allocate_info,
                descriptor_sets,
            ),
        );
    }

    pub fn allocateMemory(
        self: *const Self,
        allocate_info: *const c.VkMemoryAllocateInfo,
        memory: *c.VkDeviceMemory,
    ) !void {
        try vk.checkVulkanError(
            "Failed to allocate Vulkan memory",
            self.dispatch.AllocateMemory(
                self.device,
                allocate_info,
                self.instance.allocation_callbacks,
                memory,
            ),
        );
    }

    pub fn beginCommandBuffer(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        begin_info: *const c.VkCommandBufferBeginInfo,
    ) !void {
        std.debug.assert(command_buffer != null);

        try vk.checkVulkanError(
            "Failed to begin Vulkan command buffer",
            self.dispatch.BeginCommandBuffer(
                command_buffer,
                begin_info,
            ),
        );
    }

    pub fn bindBufferMemory(
        self: *const Self,
        buffer: c.VkBuffer,
        memory: c.VkDeviceMemory,
        offset: c.VkDeviceSize,
    ) !void {
        std.debug.assert(buffer != null);
        std.debug.assert(memory != null);

        try vk.checkVulkanError(
            "Failed to bind Vulkan buffer memory",
            self.dispatch.BindBufferMemory(
                self.device,
                buffer,
                memory,
                offset,
            ),
        );
    }

    pub fn bindImageMemory(
        self: *const Self,
        image: c.VkImage,
        memory: c.VkDeviceMemory,
        offset: c.VkDeviceSize,
    ) !void {
        std.debug.assert(image != null);
        std.debug.assert(memory != null);

        try vk.checkVulkanError(
            "Failed to bind Vulkan image memory",
            self.dispatch.BindImageMemory(
                self.device,
                image,
                memory,
                offset,
            ),
        );
    }

    pub fn cmdBeginRenderPass(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        begin_info: *const c.VkRenderPassBeginInfo,
        contents: c.VkSubpassContents,
    ) !void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdBeginRenderPass(
            command_buffer,
            begin_info,
            contents,
        );
    }

    pub fn cmdBindDescriptorSets(
        self: *const Self,
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

        self.dispatch.CmdBindDescriptorSets(
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

    pub fn cmdBindIndexBuffer(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        buffer: c.VkBuffer,
        offset: c.VkDeviceSize,
        index_type: c.VkIndexType,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdBindIndexBuffer(
            command_buffer,
            buffer,
            offset,
            index_type,
        );
    }

    pub fn cmdBindPipeline(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        pipeline_bind_point: c.VkPipelineBindPoint,
        pipeline: c.VkPipeline,
    ) void {
        std.debug.assert(command_buffer != null);
        std.debug.assert(pipeline != null);

        self.dispatch.CmdBindPipeline(
            command_buffer,
            pipeline_bind_point,
            pipeline,
        );
    }

    pub fn cmdBindVertexBuffers(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        first_binding: u32,
        binding_count: u32,
        buffers: [*c]const c.VkBuffer,
        offsets: [*c]c.VkDeviceSize,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdBindVertexBuffers(
            command_buffer,
            first_binding,
            binding_count,
            buffers,
            offsets,
        );
    }

    pub fn cmdBlitImage(
        self: *const Self,
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

        self.dispatch.CmdBlitImage(
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

    pub fn cmdCopyBuffer(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        src_buffer: c.VkBuffer,
        dst_buffer: c.VkBuffer,
        region_count: u32,
        regions: [*c]const c.VkBufferCopy,
    ) void {
        std.debug.assert(command_buffer != null);
        std.debug.assert(src_buffer != null);
        std.debug.assert(dst_buffer != null);

        self.dispatch.CmdCopyBuffer(
            command_buffer,
            src_buffer,
            dst_buffer,
            region_count,
            regions,
        );
    }

    pub fn cmdCopyBufferToImage(
        self: *const Self,
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

        self.dispatch.CmdCopyBufferToImage(
            command_buffer,
            src_buffer,
            dst_image,
            dst_image_layout,
            region_count,
            regions,
        );
    }

    pub fn cmdDraw(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdDraw(
            command_buffer,
            vertex_count,
            instance_count,
            first_vertex,
            first_instance,
        );
    }

    pub fn cmdDrawIndexed(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        index_count: u32,
        instance_count: u32,
        first_index: u32,
        vertex_offset: i32,
        first_instance: u32,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdDrawIndexed(
            command_buffer,
            index_count,
            instance_count,
            first_index,
            vertex_offset,
            first_instance,
        );
    }

    pub fn cmdEndRenderPass(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdEndRenderPass(command_buffer);
    }

    pub fn cmdPipelineBarrier(
        self: *const Self,
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

        self.dispatch.CmdPipelineBarrier(
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

    pub fn cmdSetScissor(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        first_scissor: u32,
        scissor_count: u32,
        scissors: [*c]const c.VkRect2D,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdSetScissor(
            command_buffer,
            first_scissor,
            scissor_count,
            scissors,
        );
    }

    pub fn cmdSetViewport(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        first_viewport: u32,
        viewport_count: u32,
        viewports: [*c]const c.VkViewport,
    ) void {
        std.debug.assert(command_buffer != null);

        self.dispatch.CmdSetViewport(
            command_buffer,
            first_viewport,
            viewport_count,
            viewports,
        );
    }

    pub fn createBuffer(
        self: *const Self,
        create_info: *const c.VkBufferCreateInfo,
        buffer: *c.VkBuffer,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan buffer",
            self.dispatch.CreateBuffer(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                buffer,
            ),
        );
    }

    pub fn createCommandPool(
        self: *const Self,
        create_info: *const c.VkCommandPoolCreateInfo,
        command_pool: *c.VkCommandPool,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan command pool",
            self.dispatch.CreateCommandPool(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                command_pool,
            ),
        );
    }

    pub fn createDescriptorPool(
        self: *const Self,
        create_info: *const c.VkDescriptorPoolCreateInfo,
        descriptor_pool: *c.VkDescriptorPool,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan descriptor pool",
            self.dispatch.CreateDescriptorPool(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                descriptor_pool,
            ),
        );
    }

    pub fn createDescriptorSetLayout(
        self: *const Self,
        create_info: *const c.VkDescriptorSetLayoutCreateInfo,
        descriptor_set_layout: *c.VkDescriptorSetLayout,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan descriptor set layout",
            self.dispatch.CreateDescriptorSetLayout(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                descriptor_set_layout,
            ),
        );
    }

    pub fn createFence(
        self: *const Self,
        create_info: *const c.VkFenceCreateInfo,
        fence: *c.VkFence,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan fence",
            self.dispatch.CreateFence(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                fence,
            ),
        );
    }

    pub fn createFrameBuffer(
        self: *const Self,
        create_info: *const c.VkFramebufferCreateInfo,
        frame_buffer: *c.VkFramebuffer,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan frame buffer",
            self.dispatch.CreateFramebuffer(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                frame_buffer,
            ),
        );
    }

    pub fn createGraphicsPipelines(
        self: *const Self,
        pipeline_cache: c.VkPipelineCache,
        create_info_count: u32,
        create_infos: [*c]const c.VkGraphicsPipelineCreateInfo,
        pipelines: [*c]c.VkPipeline,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan graphics pipelines",
            self.dispatch.CreateGraphicsPipelines(
                self.device,
                pipeline_cache,
                create_info_count,
                create_infos,
                self.instance.allocation_callbacks,
                pipelines,
            ),
        );
    }

    pub fn createImage(
        self: *const Self,
        create_info: *const c.VkImageCreateInfo,
        image: *c.VkImage,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan image",
            self.dispatch.CreateImage(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                image,
            ),
        );
    }

    pub fn createImageView(
        self: *const Self,
        create_info: *const c.VkImageViewCreateInfo,
        image_view: *c.VkImageView,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan image view",
            self.dispatch.CreateImageView(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                image_view,
            ),
        );
    }

    pub fn createPipelineLayout(
        self: *const Self,
        create_info: *const c.VkPipelineLayoutCreateInfo,
        pipeline_layout: *c.VkPipelineLayout,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan pipeline layout",
            self.dispatch.CreatePipelineLayout(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                pipeline_layout,
            ),
        );
    }

    pub fn createRenderPass(
        self: *const Self,
        create_info: *const c.VkRenderPassCreateInfo,
        render_pass: *c.VkRenderPass,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan render pass",
            self.dispatch.CreateRenderPass(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                render_pass,
            ),
        );
    }

    pub fn createSemaphore(
        self: *const Self,
        create_info: *const c.VkSemaphoreCreateInfo,
        semaphore: *c.VkSemaphore,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan semaphore",
            self.dispatch.CreateSemaphore(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                semaphore,
            ),
        );
    }

    pub fn createShaderModule(
        self: *const Self,
        create_info: *const c.VkShaderModuleCreateInfo,
        shader_module: *c.VkShaderModule,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan shader module",
            self.dispatch.CreateShaderModule(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                shader_module,
            ),
        );
    }

    pub fn createSwapchainKHR(
        self: *const Self,
        create_info: *const c.VkSwapchainCreateInfoKHR,
        swapchain: *c.VkSwapchainKHR,
    ) !void {
        try vk.checkVulkanError(
            "Failed to create Vulkan swapchain",
            self.dispatch.CreateSwapchainKHR(
                self.device,
                create_info,
                self.instance.allocation_callbacks,
                swapchain,
            ),
        );
    }

    pub fn destroyBuffer(
        self: *const Self,
        buffer: c.VkBuffer,
    ) void {
        std.debug.assert(buffer != null);

        self.dispatch.DestroyBuffer(
            self.device,
            buffer,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyCommandPool(
        self: *const Self,
        command_pool: c.VkCommandPool,
    ) void {
        std.debug.assert(command_pool != null);

        self.dispatch.DestroyCommandPool(
            self.device,
            command_pool,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyDescriptorPool(
        self: *const Self,
        descriptor_pool: c.VkDescriptorPool,
    ) void {
        std.debug.assert(descriptor_pool != null);

        self.dispatch.DestroyDescriptorPool(
            self.device,
            descriptor_pool,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyDescriptorSetLayout(
        self: *const Self,
        descriptor_set_layout: c.VkDescriptorSetLayout,
    ) void {
        std.debug.assert(descriptor_set_layout != null);

        self.dispatch.DestroyDescriptorSetLayout(
            self.device,
            descriptor_set_layout,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyFence(
        self: *const Self,
        fence: c.VkFence,
    ) void {
        std.debug.assert(fence != null);

        self.dispatch.DestroyFence(
            self.device,
            fence,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyFrameBuffer(
        self: *const Self,
        frame_buffer: c.VkFramebuffer,
    ) void {
        std.debug.assert(frame_buffer != null);

        self.dispatch.DestroyFramebuffer(
            self.device,
            frame_buffer,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyImage(
        self: *const Self,
        image: c.VkImage,
    ) void {
        std.debug.assert(image != null);

        self.dispatch.DestroyImage(
            self.device,
            image,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyImageView(
        self: *const Self,
        image_view: c.VkImageView,
    ) void {
        std.debug.assert(image_view != null);

        self.dispatch.DestroyImageView(
            self.device,
            image_view,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyPipeline(
        self: *const Self,
        pipeline: c.VkPipeline,
    ) void {
        std.debug.assert(pipeline != null);

        self.dispatch.DestroyPipeline(
            self.device,
            pipeline,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyPipelineLayout(
        self: *const Self,
        pipeline_layout: c.VkPipelineLayout,
    ) void {
        std.debug.assert(pipeline_layout != null);

        self.dispatch.DestroyPipelineLayout(
            self.device,
            pipeline_layout,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyRenderPass(
        self: *const Self,
        render_pass: c.VkRenderPass,
    ) void {
        std.debug.assert(render_pass != null);

        self.dispatch.DestroyRenderPass(
            self.device,
            render_pass,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroySemaphore(
        self: *const Self,
        semaphore: c.VkSemaphore,
    ) void {
        std.debug.assert(semaphore != null);

        self.dispatch.DestroySemaphore(
            self.device,
            semaphore,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroyShaderModule(
        self: *const Self,
        shader_module: c.VkShaderModule,
    ) void {
        std.debug.assert(shader_module != null);

        self.dispatch.DestroyShaderModule(
            self.device,
            shader_module,
            self.instance.allocation_callbacks,
        );
    }

    pub fn destroySwapchainKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
    ) void {
        std.debug.assert(swapchain != null);

        self.dispatch.DestroySwapchainKHR(
            self.device,
            swapchain,
            self.instance.allocation_callbacks,
        );
    }

    pub fn deviceWaitIdle(self: *const Self) !void {
        try vk.checkVulkanError(
            "Failed to wait for Vulkan device idle",
            self.dispatch.DeviceWaitIdle(self.device),
        );
    }

    pub fn endCommandBuffer(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
    ) !void {
        std.debug.assert(command_buffer != null);

        try vk.checkVulkanError(
            "Failed to end Vulkan command buffer",
            self.dispatch.EndCommandBuffer(command_buffer),
        );
    }

    pub fn freeCommandBuffers(
        self: *const Self,
        command_pool: c.VkCommandPool,
        command_buffer_count: u32,
        command_buffers: [*c]const c.VkCommandBuffer,
    ) void {
        std.debug.assert(command_pool != null);

        self.dispatch.FreeCommandBuffers(
            self.device,
            command_pool,
            command_buffer_count,
            command_buffers,
        );
    }

    pub fn freeDescriptorSets(
        self: *const Self,
        descriptor_pool: c.VkDescriptorPool,
        descriptor_set_count: u32,
        descriptor_sets: [*c]c.VkDescriptorSet,
    ) !void {
        std.debug.assert(descriptor_pool != null);

        try vk.checkVulkanError(
            "Failed to free Vulkan descriptor sets",
            self.dispatch.FreeDescriptorSets(
                self.device,
                descriptor_pool,
                descriptor_set_count,
                descriptor_sets,
            ),
        );
    }

    pub fn freeMemory(
        self: *const Self,
        memory: c.VkDeviceMemory,
    ) void {
        std.debug.assert(memory != null);

        self.dispatch.FreeMemory(
            self.device,
            memory,
            self.instance.allocation_callbacks,
        );
    }

    pub fn getBufferMemoryRequirements(
        self: *const Self,
        buffer: c.VkBuffer,
        requirements: *c.VkMemoryRequirements,
    ) void {
        std.debug.assert(buffer != null);

        self.dispatch.GetBufferMemoryRequirements(
            self.device,
            buffer,
            requirements,
        );
    }

    pub fn getDeviceQueue(
        self: *const Self,
        queue_family_index: u32,
        queue_index: u32,
        queue: *c.VkQueue,
    ) void {
        self.dispatch.GetDeviceQueue(
            self.device,
            queue_family_index,
            queue_index,
            queue,
        );
    }

    pub fn getImageMemoryRequirements(
        self: *const Self,
        image: c.VkImage,
        requirements: *c.VkMemoryRequirements,
    ) void {
        std.debug.assert(image != null);

        self.dispatch.GetImageMemoryRequirements(
            self.device,
            image,
            requirements,
        );
    }

    pub fn getImageSubresourceLayout(
        self: *const Self,
        image: c.VkImage,
        subresource: *c.VkImageSubresource,
        layout: *c.VkSubresourceLayout,
    ) void {
        std.debug.assert(image != null);

        self.dispatch.GetImageSubresourceLayout(
            self.device,
            image,
            subresource,
            layout,
        );
    }

    pub fn getPhysicalDeviceFeatures2(
        self: *const Self,
        features: *c.VkPhysicalDeviceFeatures2,
    ) void {
        self.dispatch.GetPhysicalDeviceFeatures2(
            self.physical_device,
            features,
        );
    }

    pub fn getPhysicalDeviceFormatProperties(
        self: *const Self,
        format: c.VkFormat,
        format_properties: *c.VkFormatProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceFormatProperties(
            self.physical_device,
            format,
            format_properties,
        );
    }

    pub fn getPhysicalDeviceImageFormatProperties(
        self: *const Self,
        format: c.VkFormat,
        image_type: c.VkImageType,
        tiling: c.VkImageTiling,
        usage: c.VkImageUsageFlags,
        flags: c.VkImageCreateFlags,
        image_format_properties: *c.VkImageFormatProperties,
    ) !c.VkResult {
        return self.dispatch.GetPhysicalDeviceImageFormatProperties(
            self.physical_device,
            format,
            image_type,
            tiling,
            usage,
            flags,
            image_format_properties,
        );
    }

    pub fn getPhysicalDeviceMemoryProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        memory_properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        std.debug.assert(physical_device != null);

        self.dispatch.GetPhysicalDeviceMemoryProperties(
            physical_device,
            memory_properties,
        );
    }

    pub fn getSwapchainImagesKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
        count: *u32,
        images: [*c]c.VkImage,
    ) !void {
        std.debug.assert(swapchain != null);

        const result = self.dispatch.GetSwapchainImagesKHR(
            self.device,
            swapchain,
            count,
            images,
        );
        if (result == c.VK_INCOMPLETE) {
            // For vulkan documentation this is not an error. But in our case should never happen.
            vk.log.warn("Failed to get swapchain images: incomplete", .{});
        } else {
            try vk.checkVulkanError(
                "Failed to get swapchain images",
                result,
            );
        }
    }

    pub fn getSwapchainImagesKHRAlloc(
        self: *const Self,
        allocator: std.mem.Allocator,
        swapchain: c.VkSwapchainKHR,
    ) ![]c.VkImage {
        std.debug.assert(swapchain != null);

        var count: u32 = undefined;
        try self.getSwapchainImagesKHR(
            swapchain,
            &count,
            null,
        );

        const result = try allocator.alloc(
            c.VkImage,
            count,
        );
        errdefer allocator.free(result);

        try self.getSwapchainImagesKHR(
            swapchain,
            &count,
            result.ptr,
        );
        return result;
    }

    pub fn mapMemory(
        self: *const Self,
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
            self.dispatch.MapMemory(
                self.device,
                memory,
                offset,
                size,
                flags,
                data,
            ),
        );
    }

    pub fn queuePresentKHR(
        self: *const Self,
        queue: c.VkQueue,
        present_info: *const c.VkPresentInfoKHR,
    ) !c.VkResult {
        std.debug.assert(queue != null);

        const result = self.dispatch.QueuePresentKHR(
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

    pub fn queueSubmit(
        self: *const Self,
        queue: c.VkQueue,
        submit_count: u32,
        submits: [*c]const c.VkSubmitInfo,
        fence: c.VkFence,
    ) !void {
        std.debug.assert(queue != null);
        std.debug.assert(submits != null);

        try vk.checkVulkanError(
            "Failed to submit Vulkan queue",
            self.dispatch.QueueSubmit(
                queue,
                submit_count,
                submits,
                fence,
            ),
        );
    }

    pub fn queueWaitIdle(
        self: *const Self,
        queue: c.VkQueue,
    ) !void {
        std.debug.assert(queue != null);

        try vk.checkVulkanError(
            "Failed to wait for Vulkan queue",
            self.dispatch.QueueWaitIdle(queue),
        );
    }

    pub fn resetCommandBuffer(
        self: *const Self,
        command_buffer: c.VkCommandBuffer,
        flags: c.VkCommandBufferResetFlags,
    ) !void {
        std.debug.assert(command_buffer != null);

        try vk.checkVulkanError(
            "Failed to reset Vulkan command buffer",
            self.dispatch.ResetCommandBuffer(
                command_buffer,
                flags,
            ),
        );
    }

    pub fn resetFences(
        self: *const Self,
        fence_count: u32,
        fences: [*c]c.VkFence,
    ) !void {
        try vk.checkVulkanError(
            "Failed to reset Vulkan fences",
            self.dispatch.ResetFences(
                self.device,
                fence_count,
                fences,
            ),
        );
    }

    pub fn unmapMemory(
        self: *const Self,
        memory: c.VkDeviceMemory,
    ) void {
        std.debug.assert(memory != null);

        self.dispatch.UnmapMemory(
            self.device,
            memory,
        );
    }

    pub fn updateDescriptorSets(
        self: *const Self,
        descriptor_write_count: u32,
        descriptor_writes: [*c]const c.VkWriteDescriptorSet,
        descriptor_copy_count: u32,
        descriptor_copies: [*c]const c.VkCopyDescriptorSet,
    ) void {
        self.dispatch.UpdateDescriptorSets(
            self.device,
            descriptor_write_count,
            descriptor_writes,
            descriptor_copy_count,
            descriptor_copies,
        );
    }

    pub fn waitForFences(
        self: *const Self,
        fence_count: u32,
        fences: [*c]c.VkFence,
        wait_all: c.VkBool32,
        timeout: u64,
    ) !void {
        try vk.checkVulkanError(
            "Failed to wait for Vulkan fences",
            self.dispatch.WaitForFences(
                self.device,
                fence_count,
                fences,
                wait_all,
                timeout,
            ),
        );
    }
};
