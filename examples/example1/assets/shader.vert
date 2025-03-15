#version 450

layout(binding = 0) uniform ModelViewProj {
    mat4 model;
    mat4 view;
    mat4 proj;
} u_mvp;

layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_color0;
layout(location = 2) in vec2 a_texcoord0;

layout(location = 0) out vec3 fragColor;
layout(location = 1) out vec2 fragTexCoord;

void main() {
    gl_Position = u_mvp.proj * u_mvp.view * u_mvp.model * vec4(a_position, 1.0);
    fragColor = a_color0;
    fragTexCoord = a_texcoord0;
}
