#version 450

// INPUTS
layout(location = 1) in vec2 f_tex_coord;

// OUTPUTS
layout(location = 0) out vec4 outColor;

// UNIFORMS
layout(binding = 1) uniform Material {
    vec4 base_color_factor;
    float metallic_factor;
    float roughness_factor;
    vec4 diffuse_factor;
    vec3 specular_factor;
    float glossiness_factor;
    vec3 emissive_factor;
} u_material;
layout(binding = 2) uniform sampler2D u_tex_sampler;

void main() {
    outColor = texture(u_tex_sampler, f_tex_coord);
}
