#version 450

layout(binding = 0) uniform ModelViewProj {
    mat4 model;
    mat4 view;
    mat4 proj;
} u_mvp;

layout(location = 0) in vec3 a_position;

layout(location = 1) out vec3 fragTexCoord;

void main()
{
    fragTexCoord = a_position;

    // Convert cubemap coordinates into Vulkan coordinate space
    //fragTexCoord.xy *= -1.0;

    // Remove translation from view matrix
    mat4 viewMat = mat4(mat3(u_mvp.model));
    gl_Position = u_mvp.proj * viewMat * vec4(a_position.xyz, 1.0);
}
