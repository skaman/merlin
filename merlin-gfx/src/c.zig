const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("vulkan/vulkan.h");
    @cInclude("vulkan/vk_enum_string_helper.h");
    @cInclude("ktx.h");
    if (builtin.target.os.tag == .linux) {
        @cInclude("wayland-client-protocol.h");
    }
});
