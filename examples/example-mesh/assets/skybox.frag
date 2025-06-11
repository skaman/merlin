
#version 450

// INPUTS
layout(location = 1) in vec3 f_tex_coord;

// OUTPUTS
layout(location = 0) out vec4 outColor;

// UNIFORMS
layout(binding = 1) uniform samplerCube u_tex_sampler;

void main() {
    outColor = texture(u_tex_sampler, f_tex_coord);
}
