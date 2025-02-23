const std = @import("std");

const c = @import("../../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

pub const Device = struct {
    const Self = @This();
    const Dispatch = struct {
        DestroyDevice: std.meta.Child(c.PFN_vkDestroyDevice) = undefined,
        GetDeviceQueue: std.meta.Child(c.PFN_vkGetDeviceQueue) = undefined,
        QueueSubmit: std.meta.Child(c.PFN_vkQueueSubmit) = undefined,
        QueuePresentKHR: std.meta.Child(c.PFN_vkQueuePresentKHR) = undefined,
        CreateSwapchainKHR: std.meta.Child(c.PFN_vkCreateSwapchainKHR) = undefined,
        DestroySwapchainKHR: std.meta.Child(c.PFN_vkDestroySwapchainKHR) = undefined,
        GetSwapchainImagesKHR: std.meta.Child(c.PFN_vkGetSwapchainImagesKHR) = undefined,
        CreateImageView: std.meta.Child(c.PFN_vkCreateImageView) = undefined,
        DestroyImageView: std.meta.Child(c.PFN_vkDestroyImageView) = undefined,
        CreateShaderModule: std.meta.Child(c.PFN_vkCreateShaderModule) = undefined,
        DestroyShaderModule: std.meta.Child(c.PFN_vkDestroyShaderModule) = undefined,
        CreateGraphicsPipelines: std.meta.Child(c.PFN_vkCreateGraphicsPipelines) = undefined,
        DestroyPipeline: std.meta.Child(c.PFN_vkDestroyPipeline) = undefined,
        CreatePipelineLayout: std.meta.Child(c.PFN_vkCreatePipelineLayout) = undefined,
        DestroyPipelineLayout: std.meta.Child(c.PFN_vkDestroyPipelineLayout) = undefined,
        CreateRenderPass: std.meta.Child(c.PFN_vkCreateRenderPass) = undefined,
        DestroyRenderPass: std.meta.Child(c.PFN_vkDestroyRenderPass) = undefined,
        CreateFramebuffer: std.meta.Child(c.PFN_vkCreateFramebuffer) = undefined,
        DestroyFramebuffer: std.meta.Child(c.PFN_vkDestroyFramebuffer) = undefined,
        CreateCommandPool: std.meta.Child(c.PFN_vkCreateCommandPool) = undefined,
        DestroyCommandPool: std.meta.Child(c.PFN_vkDestroyCommandPool) = undefined,
        AllocateCommandBuffers: std.meta.Child(c.PFN_vkAllocateCommandBuffers) = undefined,
        CreateSemaphore: std.meta.Child(c.PFN_vkCreateSemaphore) = undefined,
        DestroySemaphore: std.meta.Child(c.PFN_vkDestroySemaphore) = undefined,
        CreateFence: std.meta.Child(c.PFN_vkCreateFence) = undefined,
        DestroyFence: std.meta.Child(c.PFN_vkDestroyFence) = undefined,
        WaitForFences: std.meta.Child(c.PFN_vkWaitForFences) = undefined,
        ResetFences: std.meta.Child(c.PFN_vkResetFences) = undefined,
        AcquireNextImageKHR: std.meta.Child(c.PFN_vkAcquireNextImageKHR) = undefined,
        DeviceWaitIdle: std.meta.Child(c.PFN_vkDeviceWaitIdle) = undefined,
        CreateBuffer: std.meta.Child(c.PFN_vkCreateBuffer) = undefined,
        DestroyBuffer: std.meta.Child(c.PFN_vkDestroyBuffer) = undefined,
        GetBufferMemoryRequirements: std.meta.Child(c.PFN_vkGetBufferMemoryRequirements) = undefined,
        GetPhysicalDeviceMemoryProperties: std.meta.Child(c.PFN_vkGetPhysicalDeviceMemoryProperties) = undefined,
        AllocateMemory: std.meta.Child(c.PFN_vkAllocateMemory) = undefined,
        FreeMemory: std.meta.Child(c.PFN_vkFreeMemory) = undefined,
        BindBufferMemory: std.meta.Child(c.PFN_vkBindBufferMemory) = undefined,
        MapMemory: std.meta.Child(c.PFN_vkMapMemory) = undefined,
        UnmapMemory: std.meta.Child(c.PFN_vkUnmapMemory) = undefined,
    };
    const QueueFamilyIndices = struct {
        graphics_family: ?u32 = null,
        present_family: ?u32 = null,

        fn isComplete(self: QueueFamilyIndices) bool {
            return self.graphics_family != null and self.present_family != null;
        }
    };

    instance: *const vk.Instance,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    dispatch: Dispatch,
    queue_family_indices: QueueFamilyIndices,

    pub fn init(
        graphics_ctx: *const gfx.GraphicsContext,
        library: *vk.Library,
        instance: *vk.Instance,
        surface: *const vk.Surface,
    ) !Self {
        const physical_devices = try instance.enumeratePhysicalDevicesAlloc(
            graphics_ctx.allocator,
        );
        defer graphics_ctx.allocator.free(physical_devices);

        if (physical_devices.len == 0) {
            vk.log.err("No Vulkan physical devices found", .{});
            return error.NoPhysicalDevicesFound;
        }

        const device_required_extensions = [_][*:0]const u8{
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };

        var selected_physical_device: c.VkPhysicalDevice = null;
        var selected_physical_device_score: u32 = 0;
        var selected_physical_device_index: usize = 0;
        var selected_physical_device_properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
        for (physical_devices, 0..) |physical_device, index| {
            const score = try rateDeviceSuitability(
                graphics_ctx.allocator,
                instance,
                surface,
                physical_device,
                &device_required_extensions,
            );

            var properties = std.mem.zeroes(c.VkPhysicalDeviceProperties);
            instance.getPhysicalDeviceProperties(physical_device, &properties);

            vk.log.debug("---------------------------------------------------------------", .{});
            vk.log.debug("  Physical device: {d}", .{index});
            vk.log.debug("             Name: {s}", .{properties.deviceName});
            vk.log.debug("      API version: {d}.{d}.{d}", .{
                c.VK_API_VERSION_MAJOR(properties.apiVersion),
                c.VK_API_VERSION_MINOR(properties.apiVersion),
                c.VK_API_VERSION_PATCH(properties.apiVersion),
            });
            vk.log.debug("      API variant: {d}", .{
                c.VK_API_VERSION_VARIANT(properties.apiVersion),
            });
            vk.log.debug("   Driver version: {x}", .{properties.driverVersion});
            vk.log.debug("        Vendor ID: {x}", .{properties.vendorID});
            vk.log.debug("        Device ID: {x}", .{properties.deviceID});
            vk.log.debug("             Type: {s}", .{vk.getPhysicalDeviceTypeLabel(properties.deviceType)});
            vk.log.debug("            Score: {d}", .{score});

            var memory_properties = std.mem.zeroes(
                c.VkPhysicalDeviceMemoryProperties,
            );
            instance.getPhysicalDeviceMemoryProperties(
                physical_device,
                &memory_properties,
            );

            vk.log.debug("Memory type count: {d}", .{memory_properties.memoryTypeCount});
            for (0..memory_properties.memoryTypeCount) |mp_index| {
                const memory_type = memory_properties.memoryTypes[mp_index];
                vk.log.debug(
                    "              {d:0>3}: flags 0x{x:0>8}, index {d}",
                    .{ mp_index, memory_type.propertyFlags, memory_type.heapIndex },
                );
            }
            vk.log.debug("Memory heap count: {d}", .{memory_properties.memoryHeapCount});
            for (0..memory_properties.memoryHeapCount) |mh_index| {
                const memory_heap = memory_properties.memoryHeaps[mh_index];
                vk.log.debug(
                    "              {d:0>3}: size {d}, flags 0x{x:0>8}",
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

        vk.log.debug("---------------------------------------------------------------", .{});
        vk.log.debug(
            "Using physical device {d}: {s}",
            .{ selected_physical_device_index, selected_physical_device_properties.deviceName },
        );

        const queue_family_indices = try findQueueFamilies(
            graphics_ctx.allocator,
            instance,
            surface,
            selected_physical_device,
        );

        var unique_queue_families = std.ArrayList(u32).init(
            graphics_ctx.allocator,
        );
        defer unique_queue_families.deinit();
        try unique_queue_families.append(queue_family_indices.graphics_family.?);
        if (queue_family_indices.present_family != queue_family_indices.graphics_family) {
            try unique_queue_families.append(queue_family_indices.present_family.?);
        }

        var device_queue_create_infos = std.ArrayList(c.VkDeviceQueueCreateInfo).init(
            graphics_ctx.allocator,
        );
        defer device_queue_create_infos.deinit();

        const queue_priorities = [_]f32{1.0};
        for (unique_queue_families.items) |queue_family| {
            const device_queue_create_info = std.mem.zeroInit(
                c.VkDeviceQueueCreateInfo,
                .{
                    .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                    .queueFamilyIndex = queue_family,
                    .queueCount = queue_priorities.len,
                    .pQueuePriorities = &queue_priorities,
                },
            );
            try device_queue_create_infos.append(device_queue_create_info);
        }
        const physical_device_features = std.mem.zeroInit(
            c.VkPhysicalDeviceFeatures,
            .{},
        );

        const validation_layers = try vk.prepareValidationLayers(
            graphics_ctx.allocator,
            &graphics_ctx.options,
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
                .pEnabledFeatures = &physical_device_features,
            },
        );

        var device: c.VkDevice = undefined;
        try instance.createDevice(
            selected_physical_device,
            &device_create_info,
            &device,
        );

        return .{
            .instance = instance,
            .physical_device = selected_physical_device,
            .device = device,
            .dispatch = try library.load(Dispatch, instance.handle),
            .queue_family_indices = queue_family_indices,
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
        var queue_family_indices = QueueFamilyIndices{};

        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
            allocator,
            physical_device,
        );
        defer allocator.free(queue_families);

        for (queue_families, 0..) |queue_family, index| {
            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) {
                queue_family_indices.graphics_family = @intCast(index);
            }

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

            if (queue_family_indices.isComplete()) {
                break;
            }
        }

        return queue_family_indices;
    }

    fn checkDeviceExtensionSupport(
        allocator: std.mem.Allocator,
        instance: *vk.Instance,
        physical_device: c.VkPhysicalDevice,
        required_extensions: []const [*:0]const u8,
    ) !bool {
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

    pub fn queueSubmit(
        self: *const Self,
        queue: c.VkQueue,
        submit_count: u32,
        submits: [*c]const c.VkSubmitInfo,
        fence: c.VkFence,
    ) !void {
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

    pub fn queuePresentKHR(
        self: *const Self,
        queue: c.VkQueue,
        present_info: *const c.VkPresentInfoKHR,
    ) !c.VkResult {
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

    pub fn destroySwapchainKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
    ) void {
        self.dispatch.DestroySwapchainKHR(
            self.device,
            swapchain,
            self.instance.allocation_callbacks,
        );
    }

    pub fn getSwapchainImagesKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
        count: *u32,
        images: [*c]c.VkImage,
    ) !void {
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

    pub fn destroyImageView(
        self: *const Self,
        image_view: c.VkImageView,
    ) void {
        self.dispatch.DestroyImageView(
            self.device,
            image_view,
            self.instance.allocation_callbacks,
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

    pub fn destroyShaderModule(
        self: *const Self,
        shader_module: c.VkShaderModule,
    ) void {
        self.dispatch.DestroyShaderModule(
            self.device,
            shader_module,
            self.instance.allocation_callbacks,
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

    pub fn destroyPipeline(
        self: *const Self,
        pipeline: c.VkPipeline,
    ) void {
        self.dispatch.DestroyPipeline(
            self.device,
            pipeline,
            self.instance.allocation_callbacks,
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

    pub fn destroyPipelineLayout(
        self: *const Self,
        pipeline_layout: c.VkPipelineLayout,
    ) void {
        self.dispatch.DestroyPipelineLayout(
            self.device,
            pipeline_layout,
            self.instance.allocation_callbacks,
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

    pub fn destroyRenderPass(
        self: *const Self,
        render_pass: c.VkRenderPass,
    ) void {
        self.dispatch.DestroyRenderPass(
            self.device,
            render_pass,
            self.instance.allocation_callbacks,
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

    pub fn destroyFrameBuffer(
        self: *const Self,
        frame_buffer: c.VkFramebuffer,
    ) void {
        self.dispatch.DestroyFramebuffer(
            self.device,
            frame_buffer,
            self.instance.allocation_callbacks,
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

    pub fn destroyCommandPool(
        self: *const Self,
        command_pool: c.VkCommandPool,
    ) void {
        self.dispatch.DestroyCommandPool(
            self.device,
            command_pool,
            self.instance.allocation_callbacks,
        );
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

    pub fn destroySemaphore(
        self: *const Self,
        semaphore: c.VkSemaphore,
    ) void {
        self.dispatch.DestroySemaphore(
            self.device,
            semaphore,
            self.instance.allocation_callbacks,
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

    pub fn destroyFence(
        self: *const Self,
        fence: c.VkFence,
    ) void {
        self.dispatch.DestroyFence(
            self.device,
            fence,
            self.instance.allocation_callbacks,
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

    pub fn acquireNextImageKHR(
        self: *const Self,
        swapchain: c.VkSwapchainKHR,
        timeout: u64,
        semaphore: c.VkSemaphore,
        fence: c.VkFence,
        image_index: *u32,
    ) !c.VkResult {
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

    pub fn waitIdle(self: *const Self) !void {
        try vk.checkVulkanError(
            "Failed to wait for Vulkan device idle",
            self.dispatch.DeviceWaitIdle(self.device),
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

    pub fn destroyBuffer(
        self: *const Self,
        buffer: c.VkBuffer,
    ) void {
        self.dispatch.DestroyBuffer(
            self.device,
            buffer,
            self.instance.allocation_callbacks,
        );
    }

    pub fn getBufferMemoryRequirements(
        self: *const Self,
        buffer: c.VkBuffer,
        requirements: *c.VkMemoryRequirements,
    ) void {
        self.dispatch.GetBufferMemoryRequirements(
            self.device,
            buffer,
            requirements,
        );
    }

    pub fn getPhysicalDeviceMemoryProperties(
        self: *const Self,
        physical_device: c.VkPhysicalDevice,
        memory_properties: *c.VkPhysicalDeviceMemoryProperties,
    ) void {
        self.dispatch.GetPhysicalDeviceMemoryProperties(
            physical_device,
            memory_properties,
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

    pub fn freeMemory(
        self: *const Self,
        memory: c.VkDeviceMemory,
    ) void {
        self.dispatch.FreeMemory(
            self.device,
            memory,
            self.instance.allocation_callbacks,
        );
    }

    pub fn bindBufferMemory(
        self: *const Self,
        buffer: c.VkBuffer,
        memory: c.VkDeviceMemory,
        offset: c.VkDeviceSize,
    ) !void {
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

    pub fn mapMemory(
        self: *const Self,
        memory: c.VkDeviceMemory,
        offset: c.VkDeviceSize,
        size: c.VkDeviceSize,
        flags: c.VkMemoryMapFlags,
        data: [*c]?*anyopaque,
    ) !void {
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

    pub fn unmapMemory(
        self: *const Self,
        memory: c.VkDeviceMemory,
    ) void {
        self.dispatch.UnmapMemory(
            self.device,
            memory,
        );
    }
};
