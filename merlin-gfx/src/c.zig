pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vk_enum_string_helper.h");
    @cInclude("ktx.h");
    @cInclude("ktxvulkan.h");
    @cInclude("wayland-client-protocol.h");
});
