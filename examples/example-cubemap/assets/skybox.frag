
#version 450

layout(location = 1) in vec3 fragTexCoord;

layout(location = 0) out vec4 outColor;

layout(binding = 1) uniform samplerCube u_tex_sampler;

void main() {
    outColor = texture(u_tex_sampler, fragTexCoord);
}
