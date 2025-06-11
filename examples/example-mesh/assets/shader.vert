#version 450

// INPUTS
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec2 a_texcoord0;

// OUTPUTS
layout(location = 1) out vec2 f_tex_coord;

// Push constants
layout(push_constant) uniform constants
{
    mat4 model;
    mat4 view;
    mat4 proj;
} p_data;

void main() {
    gl_Position = p_data.proj * p_data.view * p_data.model * vec4(a_position, 1.0);
    f_tex_coord = a_texcoord0;
}
