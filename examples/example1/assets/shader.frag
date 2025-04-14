#version 450

//layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

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
    outColor = texture(u_tex_sampler, fragTexCoord);
    //outColor = vec4(fragColor, 1.0);
    //outColor = vec4(1.0, 0.0, 0.0, 1.0);
}
