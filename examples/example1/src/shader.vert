#version 450

layout(binding = 0) uniform ModelViewProj {
    mat4 model;
    mat4 view;
    mat4 proj;
} u_mvp;

layout(location = 0) in vec2 a_position;
layout(location = 1) in vec3 a_color0;

layout(location = 0) out vec3 fragColor;

void main() {
    gl_Position = u_mvp.proj * u_mvp.view * u_mvp.model * vec4(a_position, 0.0, 1.0);
    fragColor = a_color0;
}
