const c = @import("c.zig").c;

const font_data = @embedFile("FantasqueSansMNerdFont-Regular.ttf");

pub const CatppuccinTheme = enum {
    latte,
    frappe,
    macchiato,
    mocha,
};

pub const CatppuccinColors = struct {
    rosewater: c.ImVec4,
    flamingo: c.ImVec4,
    pink: c.ImVec4,
    mauve: c.ImVec4,
    red: c.ImVec4,
    maroon: c.ImVec4,
    peach: c.ImVec4,
    yellow: c.ImVec4,
    green: c.ImVec4,
    teal: c.ImVec4,
    sky: c.ImVec4,
    sapphire: c.ImVec4,
    blue: c.ImVec4,
    lavender: c.ImVec4,
    text: c.ImVec4,
    subtext1: c.ImVec4,
    subtext0: c.ImVec4,
    overlay2: c.ImVec4,
    overlay1: c.ImVec4,
    overlay0: c.ImVec4,
    surface2: c.ImVec4,
    surface1: c.ImVec4,
    surface0: c.ImVec4,
    base: c.ImVec4,
    mantle: c.ImVec4,
    crust: c.ImVec4,

    pub fn init(theme: CatppuccinTheme) CatppuccinColors {
        return switch (theme) {
            .latte => .{
                .rosewater = .{ .x = 0.863, .y = 0.541, .z = 0.471, .w = 1.000 },
                .flamingo = .{ .x = 0.867, .y = 0.471, .z = 0.471, .w = 1.000 },
                .pink = .{ .x = 0.918, .y = 0.463, .z = 0.796, .w = 1.000 },
                .mauve = .{ .x = 0.533, .y = 0.224, .z = 0.937, .w = 1.000 },
                .red = .{ .x = 0.824, .y = 0.059, .z = 0.224, .w = 1.000 },
                .maroon = .{ .x = 0.902, .y = 0.271, .z = 0.325, .w = 1.000 },
                .peach = .{ .x = 0.996, .y = 0.392, .z = 0.043, .w = 1.000 },
                .yellow = .{ .x = 0.875, .y = 0.557, .z = 0.114, .w = 1.000 },
                .green = .{ .x = 0.251, .y = 0.627, .z = 0.169, .w = 1.000 },
                .teal = .{ .x = 0.090, .y = 0.573, .z = 0.600, .w = 1.000 },
                .sky = .{ .x = 0.016, .y = 0.647, .z = 0.898, .w = 1.000 },
                .sapphire = .{ .x = 0.125, .y = 0.624, .z = 0.710, .w = 1.000 },
                .blue = .{ .x = 0.118, .y = 0.400, .z = 0.961, .w = 1.000 },
                .lavender = .{ .x = 0.447, .y = 0.529, .z = 0.992, .w = 1.000 },
                .text = .{ .x = 0.298, .y = 0.310, .z = 0.412, .w = 1.000 },
                .subtext1 = .{ .x = 0.361, .y = 0.373, .z = 0.467, .w = 1.000 },
                .subtext0 = .{ .x = 0.424, .y = 0.435, .z = 0.522, .w = 1.000 },
                .overlay2 = .{ .x = 0.486, .y = 0.498, .z = 0.573, .w = 1.000 },
                .overlay1 = .{ .x = 0.549, .y = 0.559, .z = 0.631, .w = 1.000 },
                .overlay0 = .{ .x = 0.612, .y = 0.631, .z = 0.690, .w = 1.000 },
                .surface2 = .{ .x = 0.669, .y = 0.690, .z = 0.741, .w = 1.000 },
                .surface1 = .{ .x = 0.737, .y = 0.753, .z = 0.800, .w = 1.000 },
                .surface0 = .{ .x = 0.800, .y = 0.816, .z = 0.855, .w = 1.000 },
                .base = .{ .x = 0.941, .y = 0.945, .z = 0.961, .w = 1.000 },
                .mantle = .{ .x = 0.902, .y = 0.914, .z = 0.937, .w = 1.000 },
                .crust = .{ .x = 0.863, .y = 0.878, .z = 0.910, .w = 1.000 },
            },
            .frappe => .{
                .rosewater = .{ .x = 0.949, .y = 0.835, .z = 0.800, .w = 1.000 },
                .flamingo = .{ .x = 0.933, .y = 0.745, .z = 0.745, .w = 1.000 },
                .pink = .{ .x = 0.957, .y = 0.722, .z = 0.894, .w = 1.000 },
                .mauve = .{ .x = 0.792, .y = 0.619, .z = 0.902, .w = 1.000 },
                .red = .{ .x = 0.906, .y = 0.510, .z = 0.518, .w = 1.000 },
                .maroon = .{ .x = 0.918, .y = 0.600, .z = 0.800, .w = 1.000 },
                .peach = .{ .x = 0.941, .y = 0.624, .z = 0.463, .w = 1.000 },
                .yellow = .{ .x = 0.898, .y = 0.722, .z = 0.565, .w = 1.000 },
                .green = .{ .x = 0.651, .y = 0.820, .z = 0.537, .w = 1.000 },
                .teal = .{ .x = 0.506, .y = 0.784, .z = 0.745, .w = 1.000 },
                .sky = .{ .x = 0.600, .y = 0.820, .z = 0.859, .w = 1.000 },
                .sapphire = .{ .x = 0.518, .y = 0.757, .z = 0.863, .w = 1.000 },
                .blue = .{ .x = 0.549, .y = 0.667, .z = 0.933, .w = 1.000 },
                .lavender = .{ .x = 0.733, .y = 0.745, .z = 0.945, .w = 1.000 },
                .text = .{ .x = 0.776, .y = 0.816, .z = 0.961, .w = 1.000 },
                .subtext1 = .{ .x = 0.710, .y = 0.749, .z = 0.883, .w = 1.000 },
                .subtext0 = .{ .x = 0.647, .y = 0.678, .z = 0.807, .w = 1.000 },
                .overlay2 = .{ .x = 0.580, .y = 0.612, .z = 0.733, .w = 1.000 },
                .overlay1 = .{ .x = 0.508, .y = 0.547, .z = 0.659, .w = 1.000 },
                .overlay0 = .{ .x = 0.451, .y = 0.475, .z = 0.604, .w = 1.000 },
                .surface2 = .{ .x = 0.384, .y = 0.416, .z = 0.553, .w = 1.000 },
                .surface1 = .{ .x = 0.318, .y = 0.341, .z = 0.553, .w = 1.000 },
                .surface0 = .{ .x = 0.255, .y = 0.271, .z = 0.345, .w = 1.000 },
                .base = .{ .x = 0.188, .y = 0.208, .z = 0.267, .w = 1.000 },
                .mantle = .{ .x = 0.161, .y = 0.173, .z = 0.236, .w = 1.000 },
                .crust = .{ .x = 0.137, .y = 0.149, .z = 0.200, .w = 1.000 },
            },
            .macchiato => .{
                .rosewater = .{ .x = 0.957, .y = 0.859, .z = 0.841, .w = 1.000 },
                .flamingo = .{ .x = 0.941, .y = 0.776, .z = 0.776, .w = 1.000 },
                .pink = .{ .x = 0.961, .y = 0.741, .z = 0.902, .w = 1.000 },
                .mauve = .{ .x = 0.776, .y = 0.627, .z = 0.965, .w = 1.000 },
                .red = .{ .x = 0.929, .y = 0.529, .z = 0.588, .w = 1.000 },
                .maroon = .{ .x = 0.933, .y = 0.600, .z = 0.627, .w = 1.000 },
                .peach = .{ .x = 0.961, .y = 0.662, .z = 0.498, .w = 1.000 },
                .yellow = .{ .x = 0.933, .y = 0.835, .z = 0.624, .w = 1.000 },
                .green = .{ .x = 0.651, .y = 0.855, .z = 0.604, .w = 1.000 },
                .teal = .{ .x = 0.545, .y = 0.839, .z = 0.792, .w = 1.000 },
                .sky = .{ .x = 0.569, .y = 0.843, .z = 0.890, .w = 1.000 },
                .sapphire = .{ .x = 0.490, .y = 0.765, .z = 0.894, .w = 1.000 },
                .blue = .{ .x = 0.541, .y = 0.678, .z = 0.955, .w = 1.000 },
                .lavender = .{ .x = 0.718, .y = 0.741, .z = 0.973, .w = 1.000 },
                .text = .{ .x = 0.792, .y = 0.827, .z = 0.961, .w = 1.000 },
                .subtext1 = .{ .x = 0.722, .y = 0.753, .z = 0.878, .w = 1.000 },
                .subtext0 = .{ .x = 0.647, .y = 0.678, .z = 0.796, .w = 1.000 },
                .overlay2 = .{ .x = 0.576, .y = 0.604, .z = 0.718, .w = 1.000 },
                .overlay1 = .{ .x = 0.502, .y = 0.529, .z = 0.635, .w = 1.000 },
                .overlay0 = .{ .x = 0.431, .y = 0.455, .z = 0.553, .w = 1.000 },
                .surface2 = .{ .x = 0.357, .y = 0.380, .z = 0.490, .w = 1.000 },
                .surface1 = .{ .x = 0.286, .y = 0.302, .z = 0.588, .w = 1.000 },
                .surface0 = .{ .x = 0.196, .y = 0.224, .z = 0.310, .w = 1.000 },
                .base = .{ .x = 0.141, .y = 0.157, .z = 0.227, .w = 1.000 },
                .mantle = .{ .x = 0.118, .y = 0.125, .z = 0.188, .w = 1.000 },
                .crust = .{ .x = 0.098, .y = 0.102, .z = 0.161, .w = 1.000 },
            },
            .mocha => .{
                .rosewater = .{ .x = 0.961, .y = 0.878, .z = 0.863, .w = 1.000 },
                .flamingo = .{ .x = 0.949, .y = 0.800, .z = 0.800, .w = 1.000 },
                .pink = .{ .x = 0.961, .y = 0.761, .z = 0.906, .w = 1.000 },
                .mauve = .{ .x = 0.796, .y = 0.651, .z = 0.969, .w = 1.000 },
                .red = .{ .x = 0.953, .y = 0.543, .z = 0.659, .w = 1.000 },
                .maroon = .{ .x = 0.922, .y = 0.627, .z = 0.675, .w = 1.000 },
                .peach = .{ .x = 0.980, .y = 0.702, .z = 0.529, .w = 1.000 },
                .yellow = .{ .x = 0.976, .y = 0.886, .z = 0.686, .w = 1.000 },
                .green = .{ .x = 0.651, .y = 0.890, .z = 0.631, .w = 1.000 },
                .teal = .{ .x = 0.580, .y = 0.886, .z = 0.835, .w = 1.000 },
                .sky = .{ .x = 0.537, .y = 0.863, .z = 0.922, .w = 1.000 },
                .sapphire = .{ .x = 0.455, .y = 0.780, .z = 0.925, .w = 1.000 },
                .blue = .{ .x = 0.537, .y = 0.706, .z = 0.980, .w = 1.000 },
                .lavender = .{ .x = 0.706, .y = 0.745, .z = 0.996, .w = 1.000 },
                .text = .{ .x = 0.804, .y = 0.839, .z = 0.957, .w = 1.000 },
                .subtext1 = .{ .x = 0.729, .y = 0.761, .z = 0.871, .w = 1.000 },
                .subtext0 = .{ .x = 0.651, .y = 0.678, .z = 0.784, .w = 1.000 },
                .overlay2 = .{ .x = 0.576, .y = 0.600, .z = 0.698, .w = 1.000 },
                .overlay1 = .{ .x = 0.498, .y = 0.518, .z = 0.612, .w = 1.000 },
                .overlay0 = .{ .x = 0.424, .y = 0.439, .z = 0.525, .w = 1.000 },
                .surface2 = .{ .x = 0.345, .y = 0.357, .z = 0.439, .w = 1.000 },
                .surface1 = .{ .x = 0.271, .y = 0.278, .z = 0.353, .w = 1.000 },
                .surface0 = .{ .x = 0.192, .y = 0.196, .z = 0.267, .w = 1.000 },
                .base = .{ .x = 0.118, .y = 0.118, .z = 0.180, .w = 1.000 },
                .mantle = .{ .x = 0.094, .y = 0.094, .z = 0.145, .w = 1.000 },
                .crust = .{ .x = 0.067, .y = 0.067, .z = 0.106, .w = 1.000 },
            },
        };
    }
};

//var _colors: CatppuccinColors = undefined;

pub fn setup(theme: CatppuccinTheme, scale: f32) void {
    const colors = CatppuccinColors.init(theme);
    const style = c.igGetStyle();
    const disable_alpha = 0.6;
    const transparent = c.ImVec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };
    const primary_color = colors.mauve;
    style.*.Colors[c.ImGuiCol_Text] = colors.text;
    style.*.Colors[c.ImGuiCol_TextDisabled] = .{
        .x = colors.text.x,
        .y = colors.text.y,
        .z = colors.text.z,
        .w = disable_alpha,
    };
    style.*.Colors[c.ImGuiCol_WindowBg] = colors.mantle;
    style.*.Colors[c.ImGuiCol_ChildBg] = transparent;
    style.*.Colors[c.ImGuiCol_PopupBg] = colors.base;
    style.*.Colors[c.ImGuiCol_Border] = colors.surface0;
    style.*.Colors[c.ImGuiCol_BorderShadow] = transparent;
    style.*.Colors[c.ImGuiCol_FrameBg] = colors.base;
    style.*.Colors[c.ImGuiCol_FrameBgHovered] = colors.surface0;
    style.*.Colors[c.ImGuiCol_FrameBgActive] = colors.surface1;
    style.*.Colors[c.ImGuiCol_TitleBg] = colors.crust;
    style.*.Colors[c.ImGuiCol_TitleBgActive] = .{
        .x = primary_color.x * colors.surface1.x,
        .y = primary_color.y * colors.surface1.y,
        .z = primary_color.z * colors.surface1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TitleBgCollapsed] = colors.crust;
    style.*.Colors[c.ImGuiCol_MenuBarBg] = colors.crust;
    style.*.Colors[c.ImGuiCol_ScrollbarBg] = colors.base;
    style.*.Colors[c.ImGuiCol_ScrollbarGrab] = .{
        .x = primary_color.x * colors.surface1.x,
        .y = primary_color.y * colors.surface1.y,
        .z = primary_color.z * colors.surface1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabHovered] = .{
        .x = primary_color.x * colors.surface2.x,
        .y = primary_color.y * colors.surface2.y,
        .z = primary_color.z * colors.surface2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabActive] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_CheckMark] = primary_color;
    style.*.Colors[c.ImGuiCol_SliderGrab] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_SliderGrabActive] = .{
        .x = primary_color.x * colors.overlay2.x,
        .y = primary_color.y * colors.overlay2.y,
        .z = primary_color.z * colors.overlay2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_Button] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ButtonHovered] = .{
        .x = primary_color.x * colors.overlay1.x,
        .y = primary_color.y * colors.overlay1.y,
        .z = primary_color.z * colors.overlay1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ButtonActive] = .{
        .x = primary_color.x * colors.overlay2.x,
        .y = primary_color.y * colors.overlay2.y,
        .z = primary_color.z * colors.overlay2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_Header] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_HeaderHovered] = .{
        .x = primary_color.x * colors.overlay1.x,
        .y = primary_color.y * colors.overlay1.y,
        .z = primary_color.z * colors.overlay1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_HeaderActive] = .{
        .x = primary_color.x * colors.overlay2.x,
        .y = primary_color.y * colors.overlay2.y,
        .z = primary_color.z * colors.overlay2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_Separator] = .{
        .x = primary_color.x * colors.surface0.x,
        .y = primary_color.y * colors.surface0.y,
        .z = primary_color.z * colors.surface0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_SeparatorHovered] = .{
        .x = primary_color.x * colors.surface1.x,
        .y = primary_color.y * colors.surface1.y,
        .z = primary_color.z * colors.surface1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_SeparatorActive] = .{
        .x = primary_color.x * colors.surface2.x,
        .y = primary_color.y * colors.surface2.y,
        .z = primary_color.z * colors.surface2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ResizeGrip] = .{
        .x = primary_color.x * colors.surface0.x,
        .y = primary_color.y * colors.surface0.y,
        .z = primary_color.z * colors.surface0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ResizeGripHovered] = .{
        .x = primary_color.x * colors.surface1.x,
        .y = primary_color.y * colors.surface1.y,
        .z = primary_color.z * colors.surface1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_ResizeGripActive] = .{
        .x = primary_color.x * colors.surface2.x,
        .y = primary_color.y * colors.surface2.y,
        .z = primary_color.z * colors.surface2.z,
        .w = 1.0,
    };

    style.*.Colors[c.ImGuiCol_Tab] = .{
        .x = primary_color.x * colors.surface1.x,
        .y = primary_color.y * colors.surface1.y,
        .z = primary_color.z * colors.surface1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TabHovered] = .{
        .x = primary_color.x * colors.surface2.x,
        .y = primary_color.y * colors.surface2.y,
        .z = primary_color.z * colors.surface2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TabSelected] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TabSelectedOverline] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TabDimmed] = .{
        .x = primary_color.x * colors.surface1.x,
        .y = primary_color.y * colors.surface1.y,
        .z = primary_color.z * colors.surface1.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TabDimmedSelected] = .{
        .x = primary_color.x * colors.surface2.x,
        .y = primary_color.y * colors.surface2.y,
        .z = primary_color.z * colors.surface2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_TabDimmedSelectedOverline] = .{
        .x = primary_color.x * colors.surface2.x,
        .y = primary_color.y * colors.surface2.y,
        .z = primary_color.z * colors.surface2.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_DockingPreview] = .{
        .x = primary_color.x,
        .y = primary_color.y,
        .z = primary_color.z,
        .w = disable_alpha,
    };
    style.*.Colors[c.ImGuiCol_DockingEmptyBg] = colors.base;
    style.*.Colors[c.ImGuiCol_PlotLines] = primary_color;
    style.*.Colors[c.ImGuiCol_PlotLinesHovered] = colors.red;
    style.*.Colors[c.ImGuiCol_PlotHistogram] = primary_color;
    style.*.Colors[c.ImGuiCol_PlotHistogramHovered] = colors.blue;
    style.*.Colors[c.ImGuiCol_TableHeaderBg] = colors.crust;
    style.*.Colors[c.ImGuiCol_TableBorderLight] = colors.surface0;
    style.*.Colors[c.ImGuiCol_TableBorderStrong] = colors.surface0;
    style.*.Colors[c.ImGuiCol_TableRowBg] = colors.base;
    style.*.Colors[c.ImGuiCol_TableRowBgAlt] = colors.mantle;
    style.*.Colors[c.ImGuiCol_TextLink] = colors.blue;
    style.*.Colors[c.ImGuiCol_TextSelectedBg] = .{
        .x = primary_color.x * colors.overlay0.x,
        .y = primary_color.y * colors.overlay0.y,
        .z = primary_color.z * colors.overlay0.z,
        .w = 1.0,
    };
    style.*.Colors[c.ImGuiCol_NavCursor] = primary_color;

    style.*.FrameBorderSize = 1.0;
    style.*.WindowBorderSize = 1.0;
    style.*.PopupBorderSize = 1.0;
    style.*.FrameRounding = 0.0;
    style.*.ScrollbarRounding = 0.0;

    style.*.TabRounding = 0.0;
    style.*.WindowTitleAlign = .{ .x = 0.5, .y = 0.5 };

    c.ImGuiStyle_ScaleAllSizes(style, scale);

    const io = c.igGetIO_Nil();
    const font_config = c.ImFontConfig_ImFontConfig();
    defer c.ImFontConfig_destroy(font_config);
    font_config.*.FontDataOwnedByAtlas = false;
    font_config.*.OversampleH = 3;
    font_config.*.OversampleV = 3;

    _ = c.ImFontAtlas_AddFontFromMemoryTTF(
        io.*.Fonts,
        @constCast(@ptrCast(font_data.ptr)),
        font_data.len,
        13.0 * scale,
        font_config,
        null,
    );

    //io.*.FontGlobalScale = 1.0 / 1.25;
}
