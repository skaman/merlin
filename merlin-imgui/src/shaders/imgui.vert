#version 450

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec2 a_texcoord0;
layout(location = 2) in vec4 a_color0;

layout(location = 0) out struct {
    vec4 color;
    vec2 uv;
} v_out;

layout(push_constant) uniform constants
{
    vec2 scale;
    vec2 translate;
} p_data;

void main() {
    v_out.uv = a_texcoord0;
    v_out.color = a_color0;
    gl_Position = vec4((a_position * p_data.scale) + p_data.translate, 0.0, 1.0);
}
