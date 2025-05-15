const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Structs
// *********************************************************************************************

const UniformBufferBinding = struct {
    buffer_handle: gfx.BufferHandle,
    offset: u32,
};

const CombinedSamplerBinding = struct {
    texture_handle: gfx.TextureHandle,
};

const UniformBinding = union(types.DescriptorBindType) {
    uniform_buffer: UniformBufferBinding,
    combined_sampler: CombinedSamplerBinding,
};

const PushConstantBinding = struct {
    shader_stage: c.VkShaderStageFlags,
    offset: u32,
    size: u32,
    data: [*c]const u8,
};

pub const CommandBuffer = struct {
    command_pool: c.VkCommandPool,
    handle: c.VkCommandBuffer,

    current_pipeline_layout: ?gfx.PipelineLayoutHandle = null,
    current_debug_options: gfx.DebugOptions = .{},
    current_render_options: gfx.RenderOptions = .{},
    current_program_handle: ?gfx.ProgramHandle = null,
    current_render_pass_handle: ?gfx.RenderPassHandle = null,
    current_vertex_buffer_handle: ?gfx.BufferHandle = null,
    current_vertex_buffer_offset: u32 = 0,
    current_index_buffer_handle: ?gfx.BufferHandle = null,
    current_index_buffer_offset: u32 = 0,
    current_uniform_bindings: std.AutoHashMap(gfx.NameHandle, UniformBinding) = undefined,
    current_push_constants: std.ArrayList(PushConstantBinding) = undefined,

    last_pipeline_layout_handle: ?gfx.PipelineLayoutHandle = null,
    last_pipeline_program_handle: ?gfx.ProgramHandle = null,
    last_pipeline_render_pass_handle: ?gfx.RenderPassHandle = null,
    last_pipeline_debug_options: gfx.DebugOptions = .{},
    last_pipeline_render_options: gfx.RenderOptions = .{},
    last_vertex_buffer_handle: ?gfx.BufferHandle = null,
    last_vertex_buffer_offset: u32 = 0,
    last_index_buffer_handle: ?gfx.BufferHandle = null,
    last_index_buffer_offset: u32 = 0,

    pub fn reset(self: *CommandBuffer) void {
        self.current_pipeline_layout = null;
        self.current_debug_options = .{};
        self.current_render_options = .{};
        self.current_program_handle = null;
        self.current_render_pass_handle = null;
        self.current_vertex_buffer_handle = null;
        self.current_vertex_buffer_offset = 0;
        self.current_index_buffer_handle = null;
        self.current_index_buffer_offset = 0;
        self.current_uniform_bindings.clearRetainingCapacity();
        self.current_push_constants.clearRetainingCapacity();

        self.last_pipeline_layout_handle = null;
        self.last_pipeline_program_handle = null;
        self.last_pipeline_render_pass_handle = null;
        self.last_pipeline_debug_options = .{};
        self.last_pipeline_render_options = .{};
        self.last_vertex_buffer_handle = null;
        self.last_vertex_buffer_offset = 0;
        self.last_index_buffer_handle = null;
        self.last_index_buffer_offset = 0;
    }
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn handleBindPipeline(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
    pipeline_layout_handle: gfx.PipelineLayoutHandle,
    render_pass_handle: gfx.RenderPassHandle,
    debug_options: gfx.DebugOptions,
    render_options: gfx.RenderOptions,
) !void {
    var command_buffer = get(command_buffer_handle);
    if (command_buffer.last_pipeline_program_handle == program_handle and
        command_buffer.last_pipeline_layout_handle == pipeline_layout_handle and
        command_buffer.last_pipeline_render_pass_handle == render_pass_handle and
        command_buffer.last_pipeline_debug_options == debug_options and
        command_buffer.last_pipeline_render_options == render_options)
    {
        return;
    }

    const pipeline = try vk.pipeline.getOrCreate(
        program_handle,
        pipeline_layout_handle,
        render_pass_handle,
        debug_options,
        render_options,
    );
    std.debug.assert(pipeline != null);

    vk.device.cmdBindPipeline(
        command_buffer.handle,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline,
    );

    command_buffer.last_pipeline_program_handle = program_handle;
    command_buffer.last_pipeline_layout_handle = pipeline_layout_handle;
    command_buffer.last_pipeline_render_pass_handle = render_pass_handle;
    command_buffer.last_pipeline_debug_options = debug_options;
    command_buffer.last_pipeline_render_options = render_options;
}

fn handleBindVertexBuffer(command_buffer_handle: gfx.CommandBufferHandle) !void {
    var command_buffer = get(command_buffer_handle);
    std.debug.assert(command_buffer.current_vertex_buffer_handle != null);

    const vertex_buffer_handle = command_buffer.current_vertex_buffer_handle.?;
    const vertex_buffer_offset = command_buffer.current_vertex_buffer_offset;
    if (command_buffer.last_vertex_buffer_handle == vertex_buffer_handle and
        command_buffer.last_vertex_buffer_offset == vertex_buffer_offset)
    {
        return;
    }

    var offsets = [_]c.VkDeviceSize{vertex_buffer_offset};

    vk.device.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        &vk.buffers.get(vertex_buffer_handle).buffer,
        @ptrCast(&offsets),
    );

    command_buffer.last_vertex_buffer_handle = vertex_buffer_handle;
    command_buffer.last_vertex_buffer_offset = vertex_buffer_offset;
}

fn handleBindIndexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_type: types.IndexType,
) !void {
    var command_buffer = get(command_buffer_handle);
    std.debug.assert(command_buffer.current_index_buffer_handle != null);

    const index_buffer_handle = command_buffer.current_index_buffer_handle.?;
    const index_buffer_offset = command_buffer.current_index_buffer_offset;
    if (command_buffer.last_index_buffer_handle == index_buffer_handle and
        command_buffer.last_index_buffer_offset == index_buffer_offset)
    {
        return;
    }

    vk.device.cmdBindIndexBuffer(
        command_buffer.handle,
        vk.buffers.get(index_buffer_handle).buffer,
        index_buffer_offset,
        switch (index_type) {
            .u8 => c.VK_INDEX_TYPE_UINT8_EXT,
            .u16 => c.VK_INDEX_TYPE_UINT16,
            .u32 => c.VK_INDEX_TYPE_UINT32,
        },
    );

    command_buffer.last_index_buffer_handle = index_buffer_handle;
    command_buffer.last_index_buffer_offset = index_buffer_offset;
}

fn handlePushDescriptorSet(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
) !void {
    var command_buffer = get(command_buffer_handle);
    const program = vk.programs.get(program_handle);
    const pipeline_layout = program.pipeline_layout;
    const layout_count = program.layout_count;
    var write_descriptor_sets = &program.write_descriptor_sets;
    var buffer_infos: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorBufferInfo = undefined;
    var image_infos: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorImageInfo = undefined;

    for (0..layout_count) |binding_index| {
        const uniform_name_handle = program.uniform_name_handles[binding_index];
        const descriptor_type = program.descriptor_types[binding_index];
        const uniform_binding = command_buffer.current_uniform_bindings.get(
            uniform_name_handle,
        ) orelse {
            vk.log.err("Failed to find uniform binding for handle", .{});
            return error.UniformBindingNotFound;
        };

        switch (descriptor_type) {
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                std.debug.assert(uniform_binding == .uniform_buffer);
                const buffer = vk.buffers.get(
                    uniform_binding.uniform_buffer.buffer_handle,
                ).buffer;
                const uniform_size = program.uniform_sizes[binding_index];
                buffer_infos[binding_index] = .{
                    .buffer = buffer,
                    .offset = uniform_binding.uniform_buffer.offset,
                    .range = uniform_size,
                };
                write_descriptor_sets[binding_index].pBufferInfo = &buffer_infos[binding_index];
            },
            c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER => {
                std.debug.assert(uniform_binding == .combined_sampler);
                const texture_handle = uniform_binding.combined_sampler.texture_handle;
                const texture = vk.textures.get(texture_handle);
                image_infos[binding_index] = .{
                    .imageLayout = texture.image_layout,
                    .imageView = texture.image_view,
                    .sampler = texture.sampler,
                };
                write_descriptor_sets[binding_index].pImageInfo = &image_infos[binding_index];
            },
            else => {
                vk.log.err(
                    "Unsupported descriptor type: {s}",
                    .{c.string_VkDescriptorType(descriptor_type)},
                );
                return error.UnsupportedDescriptorType;
            },
        }
    }

    vk.device.cmdPushDescriptorSet(
        command_buffer.handle,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline_layout,
        0,
        layout_count,
        write_descriptor_sets,
    );
}

fn handlePushConstants(
    command_buffer_handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
) !void {
    var command_buffer = get(command_buffer_handle);
    const program = vk.programs.get(program_handle);
    const pipeline_layout = program.pipeline_layout;
    const push_constants = command_buffer.current_push_constants.items;

    for (push_constants) |push_constant| {
        vk.device.cmdPushConstants(
            command_buffer.handle,
            pipeline_layout,
            push_constant.shader_stage,
            push_constant.offset,
            push_constant.size,
            push_constant.data,
        );
    }

    command_buffer.current_push_constants.clearRetainingCapacity();
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {}

pub fn deinit() void {}

pub fn create(command_pool: c.VkCommandPool) !gfx.CommandBufferHandle {
    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    var command_buffer: c.VkCommandBuffer = undefined;
    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );
    errdefer vk.device.freeCommandBuffers(
        command_pool,
        1,
        &command_buffer,
    );
    std.debug.assert(command_buffer != null);

    const command_buffer_ptr = try vk.gpa.create(CommandBuffer);
    errdefer vk.gpa.destroy(command_buffer_ptr);

    command_buffer_ptr.* = .{
        .command_pool = command_pool,
        .handle = command_buffer,
        .current_uniform_bindings = .init(vk.gpa),
        .current_push_constants = std.ArrayList(PushConstantBinding).init(vk.gpa),
    };

    vk.log.debug("Created command buffer", .{});

    return .{ .handle = @ptrCast(command_buffer_ptr) };
}

pub fn destroy(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.deinit();
    command_buffer.current_push_constants.deinit();
    vk.device.freeCommandBuffers(
        command_buffer.command_pool,
        1,
        &command_buffer.handle,
    );
    vk.gpa.destroy(command_buffer);

    vk.log.debug("Destroyed command buffer", .{});
}

pub fn beginSingleTimeCommands(command_pool: c.VkCommandPool) !c.VkCommandBuffer {
    std.debug.assert(command_pool != null);

    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    var command_buffer: c.VkCommandBuffer = undefined;
    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );
    std.debug.assert(command_buffer != null);

    const begin_info = std.mem.zeroInit(
        c.VkCommandBufferBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
            .flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        },
    );

    try vk.device.beginCommandBuffer(command_buffer, &begin_info);

    return command_buffer;
}

pub fn endSingleTimeCommands(
    command_pool: c.VkCommandPool,
    command_buffer: c.VkCommandBuffer,
    queue: c.VkQueue,
) void {
    std.debug.assert(command_pool != null);
    std.debug.assert(command_buffer != null);
    std.debug.assert(queue != null);

    defer vk.device.freeCommandBuffers(
        command_pool,
        1,
        &command_buffer,
    );

    vk.device.endCommandBuffer(command_buffer) catch {
        vk.log.err("Failed to record command buffer", .{});
        return;
    };

    const submit_info = std.mem.zeroInit(
        c.VkSubmitInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .commandBufferCount = 1,
            .pCommandBuffers = &command_buffer,
        },
    );

    vk.device.queueSubmit(
        queue,
        1,
        &submit_info,
        null,
    ) catch {
        vk.log.err("Failed to submit command buffer", .{});
        return;
    };

    vk.device.queueWaitIdle(queue) catch {
        vk.log.err("Failed to wait for queue to idle", .{});
        return;
    };
}

pub inline fn get(handle: gfx.CommandBufferHandle) *CommandBuffer {
    return @ptrCast(@alignCast(handle.handle));
}

pub fn reset(command_buffer_handle: gfx.CommandBufferHandle) !void {
    const command_buffer = get(command_buffer_handle);

    try vk.device.resetCommandBuffer(command_buffer.handle, 0);
    command_buffer.reset();
}

pub fn begin(command_buffer_handle: gfx.CommandBufferHandle) !void {
    const command_buffer = get(command_buffer_handle);
    const begin_info = std.mem.zeroInit(
        c.VkCommandBufferBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        },
    );

    try vk.device.beginCommandBuffer(
        command_buffer.handle,
        &begin_info,
    );
}

pub fn end(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = get(handle);
    try vk.device.endCommandBuffer(command_buffer.handle);
}

pub fn beginRenderPass(
    command_buffer_handle: gfx.CommandBufferHandle,
    render_pass_handle: gfx.RenderPassHandle,
    framebuffer: c.VkFramebuffer,
    extent: c.VkExtent2D,
) !void {
    std.debug.assert(framebuffer != null);
    std.debug.assert(extent.width > 0 and extent.height > 0);

    const clear_values = [_]c.VkClearValue{
        .{
            .color = .{
                .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
        .{
            .depthStencil = .{
                .depth = 1.0,
                .stencil = 0,
            },
        },
    };

    const begin_info = std.mem.zeroInit(
        c.VkRenderPassBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            .renderPass = vk.render_pass.get(render_pass_handle),
            .framebuffer = framebuffer,
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = extent,
            },
            .clearValueCount = clear_values.len,
            .pClearValues = &clear_values,
        },
    );
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_render_pass_handle = render_pass_handle;

    try vk.device.cmdBeginRenderPass(
        command_buffer.handle,
        &begin_info,
        c.VK_SUBPASS_CONTENTS_INLINE,
    );
}

pub fn endRenderPass(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdEndRenderPass(command_buffer.handle);
}

pub fn setViewport(
    command_buffer_handle: gfx.CommandBufferHandle,
    viewport: *const c.VkViewport,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdSetViewport(
        command_buffer.handle,
        0,
        1,
        viewport,
    );
}

pub fn setScissor(
    command_buffer_handle: gfx.CommandBufferHandle,
    scissor: *const c.VkRect2D,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.device.cmdSetScissor(
        command_buffer.handle,
        0,
        1,
        scissor,
    );
}

pub fn setDebug(
    command_buffer_handle: gfx.CommandBufferHandle,
    debug_options: gfx.DebugOptions,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_debug_options = debug_options;
}

pub fn setRender(
    command_buffer_handle: gfx.CommandBufferHandle,
    render_options: gfx.RenderOptions,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_render_options = render_options;
}

pub fn bindPipelineLayout(
    command_buffer_handle: gfx.CommandBufferHandle,
    pipeline_layout: gfx.PipelineLayoutHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_pipeline_layout = pipeline_layout;
}

pub fn bindProgram(
    command_buffer_handle: gfx.CommandBufferHandle,
    program: gfx.ProgramHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_program_handle = program;
}

pub fn bindVertexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    vertex_buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_vertex_buffer_handle = vertex_buffer;
    command_buffer.current_vertex_buffer_offset = offset;
}

pub fn bindIndexBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_index_buffer_handle = index_buffer;
    command_buffer.current_index_buffer_offset = offset;
}

pub fn bindUniformBuffer(
    command_buffer_handle: gfx.CommandBufferHandle,
    name: gfx.NameHandle,
    buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.put(name, .{
        .uniform_buffer = .{
            .buffer_handle = buffer,
            .offset = offset,
        },
    }) catch {
        vk.log.err("Failed to bind uniform buffer", .{});
        return;
    };
}

pub fn bindCombinedSampler(
    command_buffer_handle: gfx.CommandBufferHandle,
    name: gfx.NameHandle,
    texture: gfx.TextureHandle,
) void {
    const command_buffer = get(command_buffer_handle);
    command_buffer.current_uniform_bindings.put(name, .{
        .combined_sampler = .{
            .texture_handle = texture,
        },
    }) catch {
        vk.log.err("Failed to bind combined sampler", .{});
        return;
    };
}

pub fn pushConstants(
    command_buffer_handle: gfx.CommandBufferHandle,
    shader_stage: types.ShaderType,
    offset: u32,
    size: u32,
    data: *const u8,
) void {
    const command_buffer = get(command_buffer_handle);
    const push_constant = PushConstantBinding{
        .shader_stage = switch (shader_stage) {
            .vertex => c.VK_SHADER_STAGE_VERTEX_BIT,
            .fragment => c.VK_SHADER_STAGE_FRAGMENT_BIT,
        },
        .offset = offset,
        .size = size,
        .data = data,
    };
    command_buffer.current_push_constants.append(push_constant) catch {
        vk.log.err("Failed to push constants", .{});
        return;
    };
}

pub fn draw(
    command_buffer_handle: gfx.CommandBufferHandle,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    const command_buffer = get(command_buffer_handle);
    const current_layout = command_buffer.current_pipeline_layout;
    const current_program = command_buffer.current_program_handle;
    const current_render_pass = command_buffer.current_render_pass_handle;
    const current_debug_options = command_buffer.current_debug_options;
    const current_render_options = command_buffer.current_render_options;

    handleBindPipeline(
        command_buffer_handle,
        current_program.?,
        current_layout.?,
        current_render_pass.?,
        current_debug_options,
        current_render_options,
    ) catch {
        vk.log.err("Failed to bind Vulkan program", .{});
        return;
    };

    handleBindVertexBuffer(command_buffer_handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    handlePushConstants(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan push constants", .{});
        return;
    };

    vk.device.cmdDraw(
        command_buffer.handle,
        vertex_count,
        instance_count,
        first_vertex,
        first_instance,
    );
}

pub fn drawIndexed(
    command_buffer_handle: gfx.CommandBufferHandle,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
    index_type: types.IndexType,
) void {
    const command_buffer = get(command_buffer_handle);
    const current_layout = command_buffer.current_pipeline_layout;
    const current_program = command_buffer.current_program_handle;
    const current_render_pass = command_buffer.current_render_pass_handle;
    const current_debug_options = command_buffer.current_debug_options;
    const current_render_options = command_buffer.current_render_options;

    handleBindPipeline(
        command_buffer_handle,
        current_program.?,
        current_layout.?,
        current_render_pass.?,
        current_debug_options,
        current_render_options,
    ) catch {
        vk.log.err("Failed to bind Vulkan program", .{});
        return;
    };

    handleBindVertexBuffer(command_buffer_handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    handleBindIndexBuffer(command_buffer_handle, index_type) catch {
        vk.log.err("Failed to bind Vulkan index buffer", .{});
        return;
    };

    handlePushConstants(command_buffer_handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan push constants", .{});
        return;
    };

    vk.device.cmdDrawIndexed(
        command_buffer.handle,
        index_count,
        instance_count,
        first_index,
        vertex_offset,
        first_instance,
    );
}

pub fn beginDebugLabel(
    command_buffer_handle: gfx.CommandBufferHandle,
    label_name: []const u8,
    color: [4]f32,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.debug.beginCommandBufferLabel(
        command_buffer.handle,
        label_name,
        color,
    );
}

pub fn endDebugLabel(command_buffer_handle: gfx.CommandBufferHandle) void {
    const command_buffer = get(command_buffer_handle);
    vk.debug.endCommandBufferLabel(command_buffer.handle);
}

pub fn insertDebugLabel(
    command_buffer_handle: gfx.CommandBufferHandle,
    label_name: []const u8,
    color: [4]f32,
) void {
    const command_buffer = get(command_buffer_handle);
    vk.debug.insertCommandBufferLabel(
        command_buffer.handle,
        label_name,
        color,
    );
}
