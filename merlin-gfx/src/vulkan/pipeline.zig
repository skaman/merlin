const std = @import("std");

const utils = @import("merlin_utils");
const types = utils.gfx_types;

const c = @import("../c.zig").c;
const gfx = @import("../gfx.zig");
const vk = @import("vulkan.zig");

// *********************************************************************************************
// Constants
// *********************************************************************************************

pub const MaxVertexAttributes = 16;
pub const MaxDescriptorSetBindings = 16;
pub const MaxPushConstants = 8;
pub const MaxColorAttachments = 8;

const AttributeType = [@typeInfo(types.VertexComponentType).@"enum".fields.len][4][2]c.VkFormat{
    // i8
    [_][2]c.VkFormat{
        [_]c.VkFormat{ c.VK_FORMAT_R8_SINT, c.VK_FORMAT_R8_SNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R8G8_SINT, c.VK_FORMAT_R8G8_SNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R8G8B8A8_SINT, c.VK_FORMAT_R8G8B8A8_SNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R8G8B8A8_SINT, c.VK_FORMAT_R8G8B8A8_SNORM },
    },

    // u8
    [_][2]c.VkFormat{
        [_]c.VkFormat{ c.VK_FORMAT_R8_UINT, c.VK_FORMAT_R8_UNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R8G8_UINT, c.VK_FORMAT_R8G8_UNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R8G8B8A8_UINT, c.VK_FORMAT_R8G8B8A8_UNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R8G8B8A8_UINT, c.VK_FORMAT_R8G8B8A8_UNORM },
    },

    // i16
    [_][2]c.VkFormat{
        [_]c.VkFormat{ c.VK_FORMAT_R16_SINT, c.VK_FORMAT_R16_SNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R16G16_SINT, c.VK_FORMAT_R16G16_SNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R16G16B16_SINT, c.VK_FORMAT_R16G16B16_SNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R16G16B16A16_SINT, c.VK_FORMAT_R16G16B16A16_SNORM },
    },

    // u16
    [_][2]c.VkFormat{
        [_]c.VkFormat{ c.VK_FORMAT_R16_UINT, c.VK_FORMAT_R16_UNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R16G16_UINT, c.VK_FORMAT_R16G16_UNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R16G16B16_UINT, c.VK_FORMAT_R16G16B16_UNORM },
        [_]c.VkFormat{ c.VK_FORMAT_R16G16B16A16_UINT, c.VK_FORMAT_R16G16B16A16_UNORM },
    },

    // u32
    [_][2]c.VkFormat{
        [_]c.VkFormat{ c.VK_FORMAT_R32_UINT, c.VK_FORMAT_R32_UINT },
        [_]c.VkFormat{ c.VK_FORMAT_R32G32_UINT, c.VK_FORMAT_R32G32_UINT },
        [_]c.VkFormat{ c.VK_FORMAT_R32G32B32_UINT, c.VK_FORMAT_R32G32B32_UINT },
        [_]c.VkFormat{ c.VK_FORMAT_R32G32B32A32_UINT, c.VK_FORMAT_R32G32B32A32_UINT },
    },

    // f32
    [_][2]c.VkFormat{
        [_]c.VkFormat{ c.VK_FORMAT_R32_SFLOAT, c.VK_FORMAT_R32_SFLOAT },
        [_]c.VkFormat{ c.VK_FORMAT_R32G32_SFLOAT, c.VK_FORMAT_R32G32_SFLOAT },
        [_]c.VkFormat{ c.VK_FORMAT_R32G32B32_SFLOAT, c.VK_FORMAT_R32G32B32_SFLOAT },
        [_]c.VkFormat{ c.VK_FORMAT_R32G32B32A32_SFLOAT, c.VK_FORMAT_R32G32B32A32_SFLOAT },
    },
};

// *********************************************************************************************
// Structs
// *********************************************************************************************
const PipelineKeyContext = struct {
    pub fn hash(ctx: PipelineKeyContext, key: PipelineKey) u64 {
        _ = ctx;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&key.program_handle));
        hasher.update(std.mem.asBytes(&key.pipeline_layout_handle));
        hasher.update(std.mem.asBytes(&key.debug_options));
        hasher.update(std.mem.asBytes(&key.render_options));
        hasher.update(std.mem.asBytes(&key.color_attachment_formats));
        hasher.update(std.mem.asBytes(&key.depth_attachment_format));
        return hasher.final();
    }

    pub fn eql(ctx: PipelineKeyContext, a: PipelineKey, b: PipelineKey) bool {
        _ = ctx;
        return std.meta.eql(a.program_handle, b.program_handle) and
            std.meta.eql(a.pipeline_layout_handle, b.pipeline_layout_handle) and
            std.meta.eql(a.debug_options, b.debug_options) and
            std.meta.eql(a.render_options, b.render_options) and
            std.mem.eql(
                c.VkFormat,
                a.color_attachment_formats,
                b.color_attachment_formats,
            ) and
            a.depth_attachment_format == b.depth_attachment_format;
    }
};

const PipelineKey = struct {
    program_handle: gfx.ProgramHandle,
    pipeline_layout_handle: gfx.PipelineLayoutHandle,
    debug_options: gfx.DebugOptions,
    render_options: gfx.RenderOptions,
    color_attachment_formats: []const c.VkFormat,
    depth_attachment_format: c.VkFormat,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _pipelines: std.HashMap(
    PipelineKey,
    c.VkPipeline,
    PipelineKeyContext,
    80,
) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn blendFactorToVulkan(blend_factor: gfx.BlendFactor) c.VkBlendFactor {
    return switch (blend_factor) {
        .zero => c.VK_BLEND_FACTOR_ZERO,
        .one => c.VK_BLEND_FACTOR_ONE,
        .src_color => c.VK_BLEND_FACTOR_SRC_COLOR,
        .one_minus_src_color => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_COLOR,
        .dst_color => c.VK_BLEND_FACTOR_DST_COLOR,
        .one_minus_dst_color => c.VK_BLEND_FACTOR_ONE_MINUS_DST_COLOR,
        .src_alpha => c.VK_BLEND_FACTOR_SRC_ALPHA,
        .one_minus_src_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .dst_alpha => c.VK_BLEND_FACTOR_DST_ALPHA,
        .one_minus_dst_alpha => c.VK_BLEND_FACTOR_ONE_MINUS_DST_ALPHA,
    };
}

fn blendOpToVulkan(blend_op: gfx.BlendOp) c.VkBlendOp {
    return switch (blend_op) {
        .add => c.VK_BLEND_OP_ADD,
        .subtract => c.VK_BLEND_OP_SUBTRACT,
        .reverse_subtract => c.VK_BLEND_OP_REVERSE_SUBTRACT,
        .min => c.VK_BLEND_OP_MIN,
        .max => c.VK_BLEND_OP_MAX,
    };
}

fn compareOpToVulkan(compare_op: gfx.CompareOp) c.VkCompareOp {
    return switch (compare_op) {
        .never => c.VK_COMPARE_OP_NEVER,
        .less => c.VK_COMPARE_OP_LESS,
        .equal => c.VK_COMPARE_OP_EQUAL,
        .less_or_equal => c.VK_COMPARE_OP_LESS_OR_EQUAL,
        .greater => c.VK_COMPARE_OP_GREATER,
        .not_equal => c.VK_COMPARE_OP_NOT_EQUAL,
        .greater_or_equal => c.VK_COMPARE_OP_GREATER_OR_EQUAL,
        .always => c.VK_COMPARE_OP_ALWAYS,
    };
}

fn create(
    program_handle: gfx.ProgramHandle,
    vertex_layout: types.VertexLayout,
    debug_options: gfx.DebugOptions,
    render_options: gfx.RenderOptions,
    color_attachment_formats: []const c.VkFormat,
    depth_attachment_format: c.VkFormat,
) !c.VkPipeline {
    const binding_description = std.mem.zeroInit(
        c.VkVertexInputBindingDescription,
        .{
            .binding = 0,
            .stride = vertex_layout.stride,
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    );

    const program = vk.programs.get(program_handle);
    const vertex_shader = program.vertex_shader;
    const fragment_shader = program.fragment_shader;

    var attribute_descriptions: [MaxVertexAttributes]c.VkVertexInputAttributeDescription = undefined;
    var attribute_count: u32 = 0;
    for (vertex_shader.input_attributes) |input_attribute| {
        const attribute_data = vertex_layout.attributes[@intFromEnum(input_attribute.attribute)];
        if (attribute_data.num == 0) {
            vk.log.warn("Attribute {s} not found in vertex layout", .{input_attribute.attribute.name()});
            continue;
        }

        std.debug.assert(attribute_data.num > 0);
        std.debug.assert(attribute_data.num <= AttributeType.len);

        attribute_descriptions[attribute_count] = .{
            .location = @intCast(input_attribute.location),
            .binding = 0,
            .format = AttributeType[@intFromEnum(attribute_data.type)][@intCast(attribute_data.num - 1)][@intFromBool(attribute_data.normalized)],
            .offset = vertex_layout.offsets[@intFromEnum(input_attribute.attribute)],
        };

        attribute_count += 1;
    }

    const vertex_input_info = std.mem.zeroInit(
        c.VkPipelineVertexInputStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
            .vertexBindingDescriptionCount = 1,
            .pVertexBindingDescriptions = &binding_description,
            .vertexAttributeDescriptionCount = attribute_count,
            .pVertexAttributeDescriptions = &attribute_descriptions,
        },
    );

    const input_assembly = std.mem.zeroInit(
        c.VkPipelineInputAssemblyStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
            .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            .primitiveRestartEnable = c.VK_FALSE,
        },
    );

    const viewport_state = std.mem.zeroInit(
        c.VkPipelineViewportStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
            .viewportCount = 1,
            .scissorCount = 1,
        },
    );

    const polygon_mode = if (debug_options.wireframe) c.VK_POLYGON_MODE_LINE else c.VK_POLYGON_MODE_FILL;
    const cull_mode = switch (render_options.cull_mode) {
        .none => c.VK_CULL_MODE_NONE,
        .front => c.VK_CULL_MODE_FRONT_BIT,
        .back => c.VK_CULL_MODE_BACK_BIT,
        .front_and_back => c.VK_CULL_MODE_FRONT_AND_BACK,
    };
    const front_face = switch (render_options.front_face) {
        .counter_clockwise => c.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .clockwise => c.VK_FRONT_FACE_CLOCKWISE,
    };

    const rasterizer = std.mem.zeroInit(
        c.VkPipelineRasterizationStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = @as(c_uint, @intCast(polygon_mode)),
            .lineWidth = 1.0,
            .cullMode = @as(u32, @intCast(cull_mode)),
            .frontFace = @as(u32, @intCast(front_face)),
            .depthBiasEnable = c.VK_FALSE,
        },
    );

    const multisampling = std.mem.zeroInit(
        c.VkPipelineMultisampleStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
            .sampleShadingEnable = c.VK_FALSE,
            .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        },
    );

    const depth_test_enabled = if (render_options.depth.enabled) c.VK_TRUE else c.VK_FALSE;
    const depth_write_enabled = if (render_options.depth.write_enabled) c.VK_TRUE else c.VK_FALSE;
    const depth_compare_op = compareOpToVulkan(render_options.depth.compare_op);
    const depth_bounds_test_enabled = if (render_options.depth.depth_bounds_test_enabled) c.VK_TRUE else c.VK_FALSE;
    const depth_stencil_test_enabled = if (render_options.depth.stencil_test_enabled) c.VK_TRUE else c.VK_FALSE;

    const depth_stencil = std.mem.zeroInit(
        c.VkPipelineDepthStencilStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = depth_test_enabled,
            .depthWriteEnable = depth_write_enabled,
            .depthCompareOp = depth_compare_op,
            .depthBoundsTestEnable = depth_bounds_test_enabled,
            .stencilTestEnable = depth_stencil_test_enabled,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
        },
    );

    const blend_enabled = if (render_options.blend.enabled) c.VK_TRUE else c.VK_FALSE;
    const src_color_blend_factor = blendFactorToVulkan(render_options.blend.src_color_factor);
    const dst_color_blend_factor = blendFactorToVulkan(render_options.blend.dst_color_factor);
    const color_blend_op = blendOpToVulkan(render_options.blend.color_op);
    const src_alpha_blend_factor = blendFactorToVulkan(render_options.blend.src_alpha_factor);
    const dst_alpha_blend_factor = blendFactorToVulkan(render_options.blend.dst_alpha_factor);
    const alpha_blend_op = blendOpToVulkan(render_options.blend.alpha_op);
    var color_write_mask: c.VkColorComponentFlags = 0;
    if (render_options.blend.write_mask.r) color_write_mask |= c.VK_COLOR_COMPONENT_R_BIT;
    if (render_options.blend.write_mask.g) color_write_mask |= c.VK_COLOR_COMPONENT_G_BIT;
    if (render_options.blend.write_mask.b) color_write_mask |= c.VK_COLOR_COMPONENT_B_BIT;
    if (render_options.blend.write_mask.a) color_write_mask |= c.VK_COLOR_COMPONENT_A_BIT;

    const color_blend_attachment = std.mem.zeroInit(
        c.VkPipelineColorBlendAttachmentState,
        .{
            .blendEnable = blend_enabled,
            .srcColorBlendFactor = src_color_blend_factor,
            .dstColorBlendFactor = dst_color_blend_factor,
            .colorBlendOp = color_blend_op,
            .srcAlphaBlendFactor = src_alpha_blend_factor,
            .dstAlphaBlendFactor = dst_alpha_blend_factor,
            .alphaBlendOp = alpha_blend_op,
            .colorWriteMask = color_write_mask,
        },
    );

    const color_blending = std.mem.zeroInit(
        c.VkPipelineColorBlendStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
            .logicOpEnable = c.VK_FALSE,
            .logicOp = c.VK_LOGIC_OP_COPY,
            .attachmentCount = 1,
            .pAttachments = &color_blend_attachment,
        },
    );

    const dynamic_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state = std.mem.zeroInit(
        c.VkPipelineDynamicStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
            .dynamicStateCount = @as(u32, dynamic_states.len),
            .pDynamicStates = &dynamic_states,
        },
    );

    const stages = [_]c.VkPipelineShaderStageCreateInfo{
        c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vertex_shader.module,
            .pName = "main",
        },
        c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = fragment_shader.module,
            .pName = "main",
        },
    };

    const pipeline_rendering_create_info = std.mem.zeroInit(
        c.VkPipelineRenderingCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
            .viewMask = 0,
            .colorAttachmentCount = @as(u32, @intCast(color_attachment_formats.len)),
            .pColorAttachmentFormats = color_attachment_formats.ptr,
            .depthAttachmentFormat = depth_attachment_format,
            .stencilAttachmentFormat = c.VK_FORMAT_UNDEFINED,
        },
    );

    const pipeline_create_info = std.mem.zeroInit(
        c.VkGraphicsPipelineCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
            .pNext = &pipeline_rendering_create_info,
            .stageCount = 2,
            .pStages = &stages,
            .pVertexInputState = &vertex_input_info,
            .pInputAssemblyState = &input_assembly,
            .pViewportState = &viewport_state,
            .pRasterizationState = &rasterizer,
            .pMultisampleState = &multisampling,
            .pDepthStencilState = &depth_stencil,
            .pColorBlendState = &color_blending,
            .pDynamicState = &dynamic_state,
            .layout = program.pipeline_layout,
        },
    );

    var graphics_pipeline: c.VkPipeline = undefined;
    try vk.device.createGraphicsPipelines(
        null,
        1,
        &pipeline_create_info,
        &graphics_pipeline,
    );
    std.debug.assert(graphics_pipeline != null);

    vk.log.debug("Pipeline created:", .{});
    vk.log.debug(
        "  - Binding Description 0: binding={d}, stride={d}, inputRate={s}",
        .{
            binding_description.binding,
            binding_description.stride,
            c.string_VkVertexInputRate(binding_description.inputRate),
        },
    );
    for (0..attribute_count) |index| {
        const attribute = attribute_descriptions[index];
        vk.log.debug(
            "  - Attribute Description {d}: location={d}, binding={d}, format={s}, offset={d}",
            .{
                index,
                attribute.location,
                attribute.binding,
                c.string_VkFormat(attribute.format),
                attribute.offset,
            },
        );
    }

    return graphics_pipeline;
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init() void {
    _pipelines = .init(vk.gpa);
}

pub fn deinit() void {
    var iterator = _pipelines.valueIterator();
    while (iterator.next()) |pipeline_value| {
        vk.device.destroyPipeline(pipeline_value.*);
    }

    _pipelines.deinit();
}

pub fn getOrCreate(
    program_handle: gfx.ProgramHandle,
    layout_handle: gfx.PipelineLayoutHandle,
    // render_pass_handle: gfx.RenderPassHandle,
    debug_options: gfx.DebugOptions,
    render_options: gfx.RenderOptions,
    color_attachment_formats: []const c.VkFormat,
    depth_attachment_format: c.VkFormat,
) !c.VkPipeline {
    const key = PipelineKey{
        .program_handle = program_handle,
        .pipeline_layout_handle = layout_handle,
        .debug_options = debug_options,
        .render_options = render_options,
        .color_attachment_formats = color_attachment_formats,
        .depth_attachment_format = depth_attachment_format,
    };
    var pipeline_value = _pipelines.get(key);
    if (pipeline_value != null) {
        return pipeline_value.?;
    }

    const pipeline_layout = vk.pipeline_layouts.get(layout_handle);
    pipeline_value = try create(
        program_handle,
        pipeline_layout.layout,
        debug_options,
        render_options,
        color_attachment_formats,
        depth_attachment_format,
    );
    try _pipelines.put(key, pipeline_value.?);
    return pipeline_value.?;
}
