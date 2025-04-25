#version 450

layout(location = 0) in struct {
    vec4 color;
    vec2 uv;
} v_in;

layout(location = 0) out vec4 f_color;

layout(binding = 1) uniform sampler2D s_tex;

layout(push_constant) uniform constants
{
    layout(offset = 64) bool srgb;
} p_data;

vec4 fromLinear(vec4 linearRGB)
{
    bvec3 cutoff = lessThan(linearRGB.rgb, vec3(0.0031308));
    vec3 higher = vec3(1.055) * pow(linearRGB.rgb, vec3(1.0 / 2.4)) - vec3(0.055);
    vec3 lower = linearRGB.rgb * vec3(12.92);

    return vec4(mix(higher, lower, cutoff), linearRGB.a);
}

// Converts a color from sRGB gamma to linear light gamma
vec4 toLinear(vec4 sRGB)
{
    bvec3 cutoff = lessThan(sRGB.rgb, vec3(0.04045));
    vec3 higher = pow((sRGB.rgb + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = sRGB.rgb / vec3(12.92);

    return vec4(mix(higher, lower, cutoff), sRGB.a);
}

void main() {
    vec4 pixel = texture(s_tex, v_in.uv) * v_in.color;
    f_color = p_data.srgb ? toLinear(pixel) : pixel;
}
