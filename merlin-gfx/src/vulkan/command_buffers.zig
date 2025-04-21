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

pub const CommandBuffer = struct {
    command_pool: c.VkCommandPool,
    handle: c.VkCommandBuffer,

    current_pipeline_layout: ?gfx.PipelineLayoutHandle = null,
    current_debug_options: gfx.DebugOptions = .{},
    current_render_options: gfx.RenderOptions = .{},
    current_program: ?gfx.ProgramHandle = null,
    current_vertex_buffer: ?gfx.BufferHandle = null,
    current_vertex_buffer_offset: u32 = 0,
    current_index_buffer: ?gfx.BufferHandle = null,
    current_index_buffer_offset: u32 = 0,
    current_uniform_bindings: std.AutoHashMap(gfx.UniformHandle, UniformBinding) = undefined,

    last_pipeline_layout: ?gfx.PipelineLayoutHandle = null,
    last_pipeline_program: ?gfx.ProgramHandle = null,
    last_pipeline_debug_options: gfx.DebugOptions = .{},
    last_pipeline_render_options: gfx.RenderOptions = .{},
    last_vertex_buffer: ?gfx.BufferHandle = null,
    last_vertex_buffer_offset: u32 = 0,
    last_index_buffer: ?gfx.BufferHandle = null,
    last_index_buffer_offset: u32 = 0,
};

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn handleBindPipeline(
    handle: gfx.CommandBufferHandle,
    program_handle: gfx.ProgramHandle,
    layout_handle: gfx.PipelineLayoutHandle,
    debug_options: gfx.DebugOptions,
    render_options: gfx.RenderOptions,
) !void {
    var command_buffer = commandBufferFromHandle(handle);
    if (command_buffer.last_pipeline_program == program_handle and
        command_buffer.last_pipeline_layout == layout_handle and
        command_buffer.last_pipeline_debug_options == debug_options and
        command_buffer.last_pipeline_render_options == render_options)
    {
        return;
    }

    const pipeline = try vk.pipeline.pipeline(
        program_handle,
        layout_handle,
        debug_options,
        render_options,
    );

    vk.device.cmdBindPipeline(
        command_buffer.handle,
        c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        pipeline,
    );

    command_buffer.last_pipeline_program = program_handle;
    command_buffer.last_pipeline_layout = layout_handle;
    command_buffer.last_pipeline_debug_options = debug_options;
    command_buffer.last_pipeline_render_options = render_options;
}

fn handleBindVertexBuffer(handle: gfx.CommandBufferHandle) !void {
    var command_buffer = commandBufferFromHandle(handle);
    const vertex_buffer = command_buffer.current_vertex_buffer.?;
    const vertex_buffer_offset = command_buffer.current_vertex_buffer_offset;
    if (command_buffer.last_vertex_buffer == vertex_buffer and
        command_buffer.last_vertex_buffer_offset == vertex_buffer_offset)
    {
        return;
    }

    var offsets = [_]c.VkDeviceSize{vertex_buffer_offset};

    vk.device.cmdBindVertexBuffers(
        command_buffer.handle,
        0,
        1,
        &vk.buffers.bufferFromHandle(vertex_buffer).buffer,
        @ptrCast(&offsets),
    );

    command_buffer.last_vertex_buffer = vertex_buffer;
    command_buffer.last_vertex_buffer_offset = vertex_buffer_offset;
}

fn handleBindIndexBuffer(handle: gfx.CommandBufferHandle, index_type: types.IndexType) !void {
    var command_buffer = commandBufferFromHandle(handle);
    const index_buffer = command_buffer.current_index_buffer.?;
    const index_buffer_offset = command_buffer.current_index_buffer_offset;
    if (command_buffer.last_index_buffer == index_buffer and
        command_buffer.last_index_buffer_offset == index_buffer_offset)
    {
        return;
    }

    vk.device.cmdBindIndexBuffer(
        command_buffer.handle,
        vk.buffers.bufferFromHandle(index_buffer).buffer,
        index_buffer_offset,
        switch (index_type) {
            .u8 => c.VK_INDEX_TYPE_UINT8_EXT,
            .u16 => c.VK_INDEX_TYPE_UINT16,
            .u32 => c.VK_INDEX_TYPE_UINT32,
        },
    );

    command_buffer.last_index_buffer = index_buffer;
    command_buffer.last_index_buffer_offset = index_buffer_offset;
}

fn handlePushDescriptorSet(handle: gfx.CommandBufferHandle, program_handle: gfx.ProgramHandle) !void {
    var command_buffer = commandBufferFromHandle(handle);
    const program = vk.programs.programFromHandle(program_handle);
    const pipeline_layout = program.pipeline_layout;
    const layout_count = program.layout_count;
    var write_descriptor_sets = &program.write_descriptor_sets;
    var buffer_infos: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorBufferInfo = undefined;
    var image_infos: [vk.pipeline.MaxDescriptorSetBindings]c.VkDescriptorImageInfo = undefined;

    for (0..layout_count) |binding_index| {
        const uniform_handle = program.uniform_handles[binding_index];
        const descriptor_type = program.descriptor_types[binding_index];
        const uniform_binding = command_buffer.current_uniform_bindings.get(uniform_handle) orelse {
            vk.log.err("Failed to find uniform binding for handle", .{});
            return error.UniformBindingNotFound;
        };

        switch (descriptor_type) {
            c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER => {
                std.debug.assert(uniform_binding == .uniform_buffer);
                const buffer = vk.buffers.bufferFromHandle(uniform_binding.uniform_buffer.buffer_handle).buffer;
                const uniform_size = program.uninform_sizes[binding_index];
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
                const texture = vk.textures.textureFromHandle(texture_handle);
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

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {}

pub fn deinit() void {}

pub fn create(command_pool: c.VkCommandPool) !gfx.CommandBufferHandle {
    var command_buffer: c.VkCommandBuffer = undefined;
    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );
    errdefer vk.device.freeCommandBuffers(
        command_pool,
        1,
        &command_buffer,
    );

    const command_buffer_ptr = try vk.gpa.create(CommandBuffer);
    errdefer vk.gpa.destroy(command_buffer_ptr);

    command_buffer_ptr.* = .{
        .command_pool = command_pool,
        .handle = command_buffer,
        .current_uniform_bindings = .init(vk.gpa),
    };

    vk.log.debug("Created command buffer", .{});

    return .{ .handle = @ptrCast(command_buffer_ptr) };
}

pub fn destroy(handle: gfx.CommandBufferHandle) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_uniform_bindings.deinit();
    vk.device.freeCommandBuffers(
        command_buffer.command_pool,
        1,
        &command_buffer.handle,
    );
    vk.gpa.destroy(command_buffer);

    vk.log.debug("Destroyed command buffer", .{});
}

pub fn beginSingleTimeCommands(command_pool: c.VkCommandPool) !c.VkCommandBuffer {
    var command_buffer: c.VkCommandBuffer = undefined;
    const allocate_info = std.mem.zeroInit(
        c.VkCommandBufferAllocateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = command_pool,
            .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        },
    );

    try vk.device.allocateCommandBuffers(
        &allocate_info,
        &command_buffer,
    );

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

pub inline fn commandBufferFromHandle(handle: gfx.CommandBufferHandle) *CommandBuffer {
    return @ptrCast(@alignCast(handle.handle));
}

pub fn reset(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = commandBufferFromHandle(handle);

    try vk.device.resetCommandBuffer(command_buffer.handle, 0);

    command_buffer.current_pipeline_layout = null;
    command_buffer.current_program = null;
    command_buffer.current_vertex_buffer = null;
    command_buffer.current_vertex_buffer_offset = 0;
    command_buffer.current_index_buffer = null;
    command_buffer.current_index_buffer_offset = 0;

    command_buffer.last_pipeline_program = null;
    command_buffer.last_pipeline_layout = null;
    command_buffer.last_vertex_buffer = null;
    command_buffer.last_vertex_buffer_offset = 0;
    command_buffer.last_index_buffer = null;
    command_buffer.last_index_buffer_offset = 0;
}

pub fn begin(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = commandBufferFromHandle(handle);
    const begin_info = std.mem.zeroInit(
        c.VkCommandBufferBeginInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        },
    );

    try vk.device.beginCommandBuffer(command_buffer.handle, &begin_info);
}

pub fn end(handle: gfx.CommandBufferHandle) !void {
    const command_buffer = commandBufferFromHandle(handle);
    try vk.device.endCommandBuffer(command_buffer.handle);
}

pub fn beginRenderPass(
    handle: gfx.CommandBufferHandle,
    render_pass: c.VkRenderPass,
    framebuffer: c.VkFramebuffer,
    extent: c.VkExtent2D,
) !void {
    std.debug.assert(framebuffer != null);
    std.debug.assert(render_pass != null);

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
            .renderPass = render_pass,
            .framebuffer = framebuffer,
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = extent,
            },
            .clearValueCount = clear_values.len,
            .pClearValues = &clear_values,
        },
    );
    const command_buffer = commandBufferFromHandle(handle);

    try vk.device.cmdBeginRenderPass(
        command_buffer.handle,
        &begin_info,
        c.VK_SUBPASS_CONTENTS_INLINE,
    );
}

pub fn endRenderPass(handle: gfx.CommandBufferHandle) void {
    const command_buffer = commandBufferFromHandle(handle);
    vk.device.cmdEndRenderPass(command_buffer.handle);
}

pub fn setViewport(handle: gfx.CommandBufferHandle, viewport: *const c.VkViewport) void {
    const command_buffer = commandBufferFromHandle(handle);
    vk.device.cmdSetViewport(
        command_buffer.handle,
        0,
        1,
        viewport,
    );
}

pub fn setScissor(handle: gfx.CommandBufferHandle, scissor: *const c.VkRect2D) void {
    const command_buffer = commandBufferFromHandle(handle);
    vk.device.cmdSetScissor(
        command_buffer.handle,
        0,
        1,
        scissor,
    );
}

pub fn setDebug(handle: gfx.CommandBufferHandle, debug_options: gfx.DebugOptions) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_debug_options = debug_options;
}

pub fn setRender(handle: gfx.CommandBufferHandle, render_options: gfx.RenderOptions) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_render_options = render_options;
}

pub fn bindPipelineLayout(
    handle: gfx.CommandBufferHandle,
    pipeline_layout: gfx.PipelineLayoutHandle,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_pipeline_layout = pipeline_layout;
}

pub fn bindProgram(
    handle: gfx.CommandBufferHandle,
    program: gfx.ProgramHandle,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_program = program;
}

pub fn bindVertexBuffer(
    handle: gfx.CommandBufferHandle,
    vertex_buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_vertex_buffer = vertex_buffer;
    command_buffer.current_vertex_buffer_offset = offset;
}

pub fn bindIndexBuffer(
    handle: gfx.CommandBufferHandle,
    index_buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_index_buffer = index_buffer;
    command_buffer.current_index_buffer_offset = offset;
}

pub fn bindUniformBuffer(
    handle: gfx.CommandBufferHandle,
    uniform: gfx.UniformHandle,
    buffer: gfx.BufferHandle,
    offset: u32,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_uniform_bindings.put(uniform, .{
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
    handle: gfx.CommandBufferHandle,
    uniform: gfx.UniformHandle,
    texture: gfx.TextureHandle,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    command_buffer.current_uniform_bindings.put(uniform, .{
        .combined_sampler = .{
            .texture_handle = texture,
        },
    }) catch {
        vk.log.err("Failed to bind uniform buffer", .{});
        return;
    };
}

pub fn draw(
    handle: gfx.CommandBufferHandle,
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    const current_layout = command_buffer.current_pipeline_layout;
    const current_program = command_buffer.current_program;
    const current_debug_options = command_buffer.current_debug_options;
    const current_render_options = command_buffer.current_render_options;

    handleBindPipeline(
        handle,
        current_program.?,
        current_layout.?,
        current_debug_options,
        current_render_options,
    ) catch {
        vk.log.err("Failed to bind Vulkan program", .{});
        return;
    };

    handleBindVertexBuffer(handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
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
    handle: gfx.CommandBufferHandle,
    index_count: u32,
    instance_count: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
    index_type: types.IndexType,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    const current_layout = command_buffer.current_pipeline_layout;
    const current_program = command_buffer.current_program;
    const current_debug_options = command_buffer.current_debug_options;
    const current_render_options = command_buffer.current_render_options;

    handleBindPipeline(
        handle,
        current_program.?,
        current_layout.?,
        current_debug_options,
        current_render_options,
    ) catch {
        vk.log.err("Failed to bind Vulkan program", .{});
        return;
    };

    handleBindVertexBuffer(handle) catch {
        vk.log.err("Failed to bind Vulkan vertex buffer", .{});
        return;
    };

    handlePushDescriptorSet(handle, current_program.?) catch {
        vk.log.err("Failed to bind Vulkan descriptor set", .{});
        return;
    };

    handleBindIndexBuffer(handle, index_type) catch {
        vk.log.err("Failed to bind Vulkan index buffer", .{});
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
    handle: gfx.CommandBufferHandle,
    label_name: []const u8,
    color: [4]f32,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    vk.debug.beginCommandBufferLabel(
        command_buffer.handle,
        label_name,
        color,
    );
}

pub fn endDebugLabel(handle: gfx.CommandBufferHandle) void {
    const command_buffer = commandBufferFromHandle(handle);
    vk.debug.endCommandBufferLabel(command_buffer.handle);
}

pub fn insertDebugLabel(
    handle: gfx.CommandBufferHandle,
    label_name: []const u8,
    color: [4]f32,
) void {
    const command_buffer = commandBufferFromHandle(handle);
    vk.debug.insertCommandBufferLabel(
        command_buffer.handle,
        label_name,
        color,
    );
}
