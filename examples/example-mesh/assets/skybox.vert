#version 450

// INPUTS
layout(location = 0) in vec3 a_position;

// OUTPUTS
layout(location = 1) out vec3 f_tex_coord;

// Push constants
layout(push_constant) uniform constants
{
    mat4 model;
    mat4 view;
    mat4 proj;
} p_data;

void main()
{
    f_tex_coord = a_position;

    // Remove translation from view matrix
    mat4 view_mat = mat4(mat3(p_data.model));
    gl_Position = p_data.proj * view_mat * vec4(a_position.xyz, 1.0);
}
