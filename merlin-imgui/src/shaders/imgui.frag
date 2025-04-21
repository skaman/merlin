#version 450

layout(location = 0) in struct {
    vec4 color;
    vec2 uv;
} v_in;

layout(location = 0) out vec4 f_color;

layout(binding = 1) uniform sampler2D s_tex;

void main() {
    f_color = texture(s_tex, v_in.uv) * v_in.color;
}
