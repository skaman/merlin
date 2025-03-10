pub const c = @cImport({
    @cInclude("stb_image.h");
    @cInclude("stb_image_resize2.h");
    @cInclude("ktx.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("GL/glcorearb.h");
});
