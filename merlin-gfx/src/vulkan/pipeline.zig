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

const PipelineKey = struct {
    program: gfx.ProgramHandle,
    layout: gfx.PipelineLayoutHandle,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var pipelines: std.AutoHashMap(PipelineKey, c.VkPipeline) = undefined;

// *********************************************************************************************
// Private API
// *********************************************************************************************

pub fn create(
    program: gfx.ProgramHandle,
    render_pass: c.VkRenderPass,
    vertex_layout: types.VertexLayout,
) !c.VkPipeline {
    const binding_description = std.mem.zeroInit(
        c.VkVertexInputBindingDescription,
        .{
            .binding = 0,
            .stride = vertex_layout.stride,
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        },
    );

    const vertex_shader = vk.programs.vertexShader(program);
    const fragment_shader = vk.programs.fragmentShader(program);

    var attribute_descriptions: [MaxVertexAttributes]c.VkVertexInputAttributeDescription = undefined;
    var attribute_count: u32 = 0;
    for (vk.shaders.getInputAttributes(vertex_shader)) |input_attribute| {
        const attribute_data = vertex_layout.attributes[@intFromEnum(input_attribute.attribute)];
        if (attribute_data.num == 0) {
            std.log.warn("Attribute {} not found in vertex layout", .{input_attribute.attribute});
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
            //.pViewports = &viewport,
            .scissorCount = 1,
            //.pScissors = &scissor,
        },
    );

    const rasterizer = std.mem.zeroInit(
        c.VkPipelineRasterizationStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
            .depthClampEnable = c.VK_FALSE,
            .rasterizerDiscardEnable = c.VK_FALSE,
            .polygonMode = c.VK_POLYGON_MODE_FILL,
            .lineWidth = 1.0,
            .cullMode = c.VK_CULL_MODE_BACK_BIT,
            .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
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

    const depth_stencil = std.mem.zeroInit(
        c.VkPipelineDepthStencilStateCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
            .depthTestEnable = c.VK_TRUE,
            .depthWriteEnable = c.VK_TRUE,
            .depthCompareOp = c.VK_COMPARE_OP_LESS,
            .depthBoundsTestEnable = c.VK_FALSE,
            .stencilTestEnable = c.VK_FALSE,
            .minDepthBounds = 0.0,
            .maxDepthBounds = 1.0,
        },
    );

    const color_blend_attachment = std.mem.zeroInit(
        c.VkPipelineColorBlendAttachmentState,
        .{
            .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
            .blendEnable = c.VK_FALSE,
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
            .module = vk.shaders.getShaderModule(vertex_shader),
            .pName = "main",
        },
        c.VkPipelineShaderStageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = vk.shaders.getShaderModule(fragment_shader),
            .pName = "main",
        },
    };

    const pipeline_create_info = std.mem.zeroInit(
        c.VkGraphicsPipelineCreateInfo,
        .{
            .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
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
            .layout = vk.programs.pipelineLayout(program),
            .renderPass = render_pass,
            .subpass = 0,
            //.basePipelineHandle = c.VK_NULL_HANDLE,
        },
    );

    var graphics_pipeline: c.VkPipeline = undefined;
    try vk.device.createGraphicsPipelines(
        null,
        1,
        &pipeline_create_info,
        &graphics_pipeline,
    );

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
    pipelines = .init(vk.gpa);
}

pub fn deinit() void {
    var iterator = pipelines.valueIterator();
    while (iterator.next()) |pipeline_value| {
        vk.device.destroyPipeline(pipeline_value.*);
    }

    pipelines.deinit();
}

pub fn pipeline(
    program_handle: gfx.ProgramHandle,
    layout_handle: gfx.PipelineLayoutHandle,
) !c.VkPipeline {
    const key = PipelineKey{
        .program = program_handle,
        .layout = layout_handle,
    };
    var pipeline_value = pipelines.get(key);
    if (pipeline_value != null) {
        return pipeline_value.?;
    }

    const vertex_layout = vk.pipeline_layouts.layout(layout_handle);
    pipeline_value = try create(
        program_handle,
        vk.main_render_pass,
        vertex_layout.*,
    );
    try pipelines.put(key, pipeline_value.?);
    return pipeline_value.?;
}
