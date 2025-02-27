pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vk_enum_string_helper.h");
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});
