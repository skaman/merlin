const std = @import("std");

const gfx = @import("merlin_gfx");
const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;

const c = @import("c.zig").c;

// *********************************************************************************************
// Constants
// *********************************************************************************************

const log = std.log.scoped(.imgui);

const frag_shader_code = @embedFile("imgui.frag.bin");
const vert_shader_code = @embedFile("imgui.vert.bin");

// *********************************************************************************************
// Structs
// *********************************************************************************************

pub const Options = struct {
    window_handle: platform.WindowHandle,
};

const UniformData = struct {
    scale: [2]f32,
    translate: [2]f32,
    srgb: bool,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var main_window_handle: platform.WindowHandle = undefined;
var context: ?*c.ImGuiContext = undefined;
var font_texture_handle: gfx.TextureHandle = undefined;
var vert_shader_handle: gfx.ShaderHandle = undefined;
var frag_shader_handle: gfx.ShaderHandle = undefined;
var program_handle: gfx.ProgramHandle = undefined;
var tex_uniform_handle: gfx.UniformHandle = undefined;
var uniform_data_handle: gfx.UniformHandle = undefined;
var uniform_data_buffer_handle: gfx.BufferHandle = undefined;
var pipeline_layout_handle: gfx.PipelineLayoutHandle = undefined;
var vertex_buffer_handle: ?gfx.BufferHandle = null;
var vertex_buffer_size: u32 = 0;
var index_buffer_handle: ?gfx.BufferHandle = null;
var index_buffer_size: u32 = 0;

// *********************************************************************************************
// Private API
// *********************************************************************************************

fn imVectorGrowCapacity(vector_ptr: anytype, size: u32) u32 {
    const new_capacity = if (vector_ptr.*.Capacity > 0) @divTrunc(vector_ptr.*.Capacity + vector_ptr.*.Capacity, 2) else 8;
    return @max(@as(u32, @intCast(new_capacity)), size);
}

fn imVectorResize(vector_ptr: anytype, new_size: u32) void {
    if (new_size > vector_ptr.*.Capacity) imVectorReserve(
        vector_ptr,
        imVectorGrowCapacity(vector_ptr, new_size),
    );
    vector_ptr.*.Size = @intCast(new_size);
}

fn imVectorReserve(vector_ptr: anytype, new_capacity: u32) void {
    if (new_capacity <= vector_ptr.*.Capacity) return;
    const type_size = @sizeOf(@TypeOf(vector_ptr.*.Data.*));
    const new_data = c.igMemAlloc(new_capacity * type_size);
    if (vector_ptr.*.Data != null) {
        const existing_size: usize = @intCast(vector_ptr.*.Size * type_size);
        const dest_ptr: [*]u8 = @ptrCast(new_data);
        const src_ptr: [*]u8 = @ptrCast(vector_ptr.*.Data);
        @memcpy(dest_ptr[0..existing_size], src_ptr[0..existing_size]);
        c.igMemFree(vector_ptr.*.Data);
    }
    vector_ptr.*.Data = @ptrCast(@alignCast(new_data));
    vector_ptr.*.Capacity = @intCast(new_capacity);
}

fn imVectorPushBack(vector_ptr: anytype, value: anytype) void {
    if (vector_ptr.*.Size == vector_ptr.*.Capacity) imVectorReserve(
        vector_ptr,
        imVectorGrowCapacity(vector_ptr, @intCast(vector_ptr.*.Size + 1)),
    );

    const type_size = @sizeOf(@TypeOf(vector_ptr.*.Data.*));
    const dest_ptr: [*]u8 = @ptrCast(vector_ptr.*.Data);
    const src_ptr: [*]const u8 = @ptrCast(&value);
    const dest_offset: usize = @intCast(vector_ptr.*.Size * type_size);
    @memcpy(dest_ptr[dest_offset..], src_ptr[0..type_size]);
    vector_ptr.*.Size += 1;
}

fn createFontsTexture() !gfx.TextureHandle {
    const io = c.igGetIO_Nil();
    var pixels: [*c]u8 = undefined;
    var width: c_int = 0;
    var height: c_int = 0;

    c.ImFontAtlas_GetTexDataAsRGBA32(
        io.*.Fonts,
        &pixels,
        &width,
        &height,
        null,
    );
    const size: u32 = @intCast(width * height * 4);
    return try gfx.createTextureFromMemory(pixels[0..size], .{
        .format = .rgba8,
        .width = @intCast(width),
        .height = @intCast(height),
        .debug_name = "ImGui Font Texture",
    });
}

fn updateMonitors() !void {
    const platform_io = c.igGetPlatformIO_Nil();
    imVectorResize(&platform_io.*.Monitors, 0);

    const monitors = try platform.monitors();
    for (monitors) |monitor| {
        const platform_monitor: c.ImGuiPlatformMonitor = .{
            .MainPos = c.ImVec2{
                .x = @floatFromInt(monitor.position[0]),
                .y = @floatFromInt(monitor.position[1]),
            },
            .MainSize = c.ImVec2{
                .x = @floatFromInt(monitor.size[0]),
                .y = @floatFromInt(monitor.size[1]),
            },
            .WorkPos = c.ImVec2{
                .x = @floatFromInt(monitor.work_area[0]),
                .y = @floatFromInt(monitor.work_area[1]),
            },
            .WorkSize = c.ImVec2{
                .x = @floatFromInt(monitor.work_area[2]),
                .y = @floatFromInt(monitor.work_area[3]),
            },
            .DpiScale = monitor.scale,
            .PlatformHandle = null,
        };

        imVectorPushBack(&platform_io.*.Monitors, platform_monitor);
    }
}

fn updateMouseCursor() !void {
    const io = c.igGetIO_Nil();
    if (io.*.ConfigFlags & c.ImGuiConfigFlags_NoMouseCursorChange != 0 or
        platform.cursorMode(main_window_handle) == .disabled)
    {
        return;
    }

    const imgui_cursor = c.igGetMouseCursor();
    const platform_io = c.igGetPlatformIO_Nil();

    for (0..@intCast(platform_io.*.Viewports.Size)) |i| {
        const viewport = platform_io.*.Viewports.Data[i];
        const window_handle: platform.WindowHandle = @enumFromInt(@intFromPtr(viewport.*.PlatformHandle));
        if (imgui_cursor == c.ImGuiMouseCursor_None or io.*.MouseDrawCursor) {
            platform.setCursorMode(window_handle, .hidden);
        } else {
            platform.setCursor(window_handle, switch (imgui_cursor) {
                c.ImGuiMouseCursor_Arrow => .arrow,
                c.ImGuiMouseCursor_TextInput => .text_input,
                c.ImGuiMouseCursor_ResizeAll => .resize_all,
                c.ImGuiMouseCursor_ResizeNS => .resize_ns,
                c.ImGuiMouseCursor_ResizeEW => .resize_ew,
                c.ImGuiMouseCursor_ResizeNESW => .resize_nesw,
                c.ImGuiMouseCursor_ResizeNWSE => .resize_nwse,
                c.ImGuiMouseCursor_Hand => .hand,
                c.ImGuiMouseCursor_NotAllowed => .not_allowed,
                else => .arrow,
            });
            platform.setCursorMode(window_handle, .normal);
        }
    }
}

fn windowFocusCallback(
    _: platform.WindowHandle,
    focused: bool,
) void {
    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddFocusEvent(io, focused);
}

fn cursorPositionCallback(
    window_handle: platform.WindowHandle,
    position: [2]f32,
) void {
    const io = c.igGetIO_Nil();
    var position_x = position[0];
    var position_y = position[1];
    if (io.*.ConfigFlags & c.ImGuiConfigFlags_ViewportsEnable != 0) {
        const window_pos = platform.windowPosition(window_handle);
        position_x += @floatFromInt(window_pos[0]);
        position_y += @floatFromInt(window_pos[1]);
    }
    c.ImGuiIO_AddMousePosEvent(io, position_x, position_y);
}

fn mouseButtonCallback(
    _: platform.WindowHandle,
    button: platform.MouseButton,
    action: platform.MouseButtonAction,
) void {
    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddMouseButtonEvent(io, @intFromEnum(button), action == .press);
}

fn mouseScrollCallback(
    _: platform.WindowHandle,
    x_scroll: f32,
    y_scroll: f32,
) void {
    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddMouseWheelEvent(io, x_scroll, y_scroll);
}

fn keyToImGuiKey(key: platform.Key) c.ImGuiKey {
    return switch (key) {
        .space => c.ImGuiKey_Space,
        .apostrophe => c.ImGuiKey_Apostrophe,
        .comma => c.ImGuiKey_Comma,
        .minus => c.ImGuiKey_Minus,
        .period => c.ImGuiKey_Period,
        .slash => c.ImGuiKey_Slash,
        .zero => c.ImGuiKey_0,
        .one => c.ImGuiKey_1,
        .two => c.ImGuiKey_2,
        .three => c.ImGuiKey_3,
        .four => c.ImGuiKey_4,
        .five => c.ImGuiKey_5,
        .six => c.ImGuiKey_6,
        .seven => c.ImGuiKey_7,
        .eight => c.ImGuiKey_8,
        .nine => c.ImGuiKey_9,
        .semicolon => c.ImGuiKey_Semicolon,
        .equal => c.ImGuiKey_Equal,
        .a => c.ImGuiKey_A,
        .b => c.ImGuiKey_B,
        .c => c.ImGuiKey_C,
        .d => c.ImGuiKey_D,
        .e => c.ImGuiKey_E,
        .f => c.ImGuiKey_F,
        .g => c.ImGuiKey_G,
        .h => c.ImGuiKey_H,
        .i => c.ImGuiKey_I,
        .j => c.ImGuiKey_J,
        .k => c.ImGuiKey_K,
        .l => c.ImGuiKey_L,
        .m => c.ImGuiKey_M,
        .n => c.ImGuiKey_N,
        .o => c.ImGuiKey_O,
        .p => c.ImGuiKey_P,
        .q => c.ImGuiKey_Q,
        .r => c.ImGuiKey_R,
        .s => c.ImGuiKey_S,
        .t => c.ImGuiKey_T,
        .u => c.ImGuiKey_U,
        .v => c.ImGuiKey_V,
        .w => c.ImGuiKey_W,
        .x => c.ImGuiKey_X,
        .y => c.ImGuiKey_Y,
        .z => c.ImGuiKey_Z,
        .left_bracket => c.ImGuiKey_LeftBracket,
        .backslash => c.ImGuiKey_Backslash,
        .right_bracket => c.ImGuiKey_RightBracket,
        .grave_accent => c.ImGuiKey_GraveAccent,
        .world_1 => c.ImGuiKey_Oem102,
        .world_2 => c.ImGuiKey_Oem102,
        .escape => c.ImGuiKey_Escape,
        .enter => c.ImGuiKey_Enter,
        .tab => c.ImGuiKey_Tab,
        .backspace => c.ImGuiKey_Backspace,
        .insert => c.ImGuiKey_Insert,
        .del => c.ImGuiKey_Delete,
        .right => c.ImGuiKey_RightArrow,
        .left => c.ImGuiKey_LeftArrow,
        .down => c.ImGuiKey_DownArrow,
        .up => c.ImGuiKey_UpArrow,
        .page_up => c.ImGuiKey_PageUp,
        .page_down => c.ImGuiKey_PageDown,
        .home => c.ImGuiKey_Home,
        .end => c.ImGuiKey_End,
        .caps_lock => c.ImGuiKey_CapsLock,
        .scroll_lock => c.ImGuiKey_ScrollLock,
        .num_lock => c.ImGuiKey_NumLock,
        .print_screen => c.ImGuiKey_PrintScreen,
        .pause => c.ImGuiKey_Pause,
        .f1 => c.ImGuiKey_F1,
        .f2 => c.ImGuiKey_F2,
        .f3 => c.ImGuiKey_F3,
        .f4 => c.ImGuiKey_F4,
        .f5 => c.ImGuiKey_F5,
        .f6 => c.ImGuiKey_F6,
        .f7 => c.ImGuiKey_F7,
        .f8 => c.ImGuiKey_F8,
        .f9 => c.ImGuiKey_F9,
        .f10 => c.ImGuiKey_F10,
        .f11 => c.ImGuiKey_F11,
        .f12 => c.ImGuiKey_F12,
        .f13 => c.ImGuiKey_F13,
        .f14 => c.ImGuiKey_F14,
        .f15 => c.ImGuiKey_F15,
        .f16 => c.ImGuiKey_F16,
        .f17 => c.ImGuiKey_F17,
        .f18 => c.ImGuiKey_F18,
        .f19 => c.ImGuiKey_F19,
        .f20 => c.ImGuiKey_F20,
        .f21 => c.ImGuiKey_F21,
        .f22 => c.ImGuiKey_F22,
        .f23 => c.ImGuiKey_F23,
        .f24 => c.ImGuiKey_F24,
        .f25 => c.ImGuiKey_Oem102,
        .numpad_0 => c.ImGuiKey_Keypad0,
        .numpad_1 => c.ImGuiKey_Keypad1,
        .numpad_2 => c.ImGuiKey_Keypad2,
        .numpad_3 => c.ImGuiKey_Keypad3,
        .numpad_4 => c.ImGuiKey_Keypad4,
        .numpad_5 => c.ImGuiKey_Keypad5,
        .numpad_6 => c.ImGuiKey_Keypad6,
        .numpad_7 => c.ImGuiKey_Keypad7,
        .numpad_8 => c.ImGuiKey_Keypad8,
        .numpad_9 => c.ImGuiKey_Keypad9,
        .numpad_decimal => c.ImGuiKey_KeypadDecimal,
        .numpad_divide => c.ImGuiKey_KeypadDivide,
        .numpad_multiply => c.ImGuiKey_KeypadMultiply,
        .numpad_subtract => c.ImGuiKey_KeypadSubtract,
        .numpad_add => c.ImGuiKey_KeypadAdd,
        .numpad_enter => c.ImGuiKey_KeypadEnter,
        .numpad_equal => c.ImGuiKey_KeypadEqual,
        .left_shift => c.ImGuiKey_LeftShift,
        .left_control => c.ImGuiKey_LeftCtrl,
        .left_alt => c.ImGuiKey_LeftAlt,
        .left_super => c.ImGuiKey_LeftSuper,
        .right_shift => c.ImGuiKey_RightShift,
        .right_control => c.ImGuiKey_RightCtrl,
        .right_alt => c.ImGuiKey_RightAlt,
        .right_super => c.ImGuiKey_RightSuper,
        .menu => c.ImGuiKey_Menu,
    };
}

fn keyCallback(
    _: platform.WindowHandle,
    key: platform.Key,
    _: i32,
    action: platform.KeyAction,
    modifiers: platform.KeyModifier,
) void {
    if (action != .press and action != .release) return;

    _ = modifiers;
    const io = c.igGetIO_Nil();
    const imgui_key = keyToImGuiKey(key);
    c.ImGuiIO_AddKeyEvent(io, imgui_key, action == .press);
}

fn charCallback(
    _: platform.WindowHandle,
    character: u32,
) void {
    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddInputCharacter(io, @intCast(character));
}

fn draw(draw_data: [*c]c.ImDrawData) !void {
    if (draw_data.*.TotalVtxCount > 0) {
        const framebuffer_size = platform.windowFramebufferSize(main_window_handle);
        const vertex_size: u32 = @intCast(@sizeOf(c.ImDrawVert) * draw_data.*.TotalVtxCount);
        const index_size: u32 = @intCast(@sizeOf(c.ImDrawIdx) * draw_data.*.TotalIdxCount);

        if (vertex_buffer_handle == null or vertex_buffer_size < vertex_size) {
            if (vertex_buffer_handle) |handle| {
                gfx.destroyBuffer(handle);
            }
            vertex_buffer_handle = try gfx.createBuffer(
                vertex_size,
                .{ .vertex = true },
                .host,
                .{ .debug_name = "ImGui Vertex Buffer" },
            );
            vertex_buffer_size = vertex_size;
        }

        if (index_buffer_handle == null or index_buffer_size < index_size) {
            if (index_buffer_handle) |handle| {
                gfx.destroyBuffer(handle);
            }
            index_buffer_handle = try gfx.createBuffer(
                index_size,
                .{ .index = true },
                .host,
                .{ .debug_name = "ImGui Index Buffer" },
            );
            index_buffer_size = index_size;
        }

        var vertex_offset: u32 = 0;
        var index_offset: u32 = 0;
        for (0..@intCast(draw_data.*.CmdListsCount)) |i| {
            const cmd_list = draw_data.*.CmdLists.Data[i];

            const vertex_count: usize = @intCast(cmd_list.*.VtxBuffer.Size);
            const vertex_cmd_size: usize = @intCast(@sizeOf(c.ImDrawVert) * vertex_count);
            const vertex_cmd_data = cmd_list.*.VtxBuffer.Data[0..vertex_count];
            try gfx.updateBufferFromMemory(
                vertex_buffer_handle.?,
                @ptrCast(vertex_cmd_data),
                vertex_offset,
            );
            vertex_offset += @intCast(vertex_cmd_size);

            const index_count: usize = @intCast(cmd_list.*.IdxBuffer.Size);
            const index_cmd_size: usize = @intCast(@sizeOf(c.ImDrawIdx) * index_count);
            const index_cmd_data = cmd_list.*.IdxBuffer.Data[0..index_count];
            try gfx.updateBufferFromMemory(
                index_buffer_handle.?,
                @ptrCast(index_cmd_data),
                index_offset,
            );
            index_offset += @intCast(index_cmd_size);
        }

        const scale: [2]f32 = .{
            2 / draw_data.*.DisplaySize.x,
            2 / draw_data.*.DisplaySize.y,
        };

        const translate: [2]f32 = .{
            -1 - draw_data.*.DisplayPos.x * scale[0],
            -1 - draw_data.*.DisplayPos.y * scale[1],
        };
        const scale_translate = UniformData{
            .scale = scale,
            .translate = translate,
            .srgb = true,
        };
        const scale_translate_ptr: [*]const u8 = @ptrCast(&scale_translate);
        try gfx.updateBufferFromMemory(
            uniform_data_buffer_handle,
            scale_translate_ptr[0..@sizeOf(UniformData)],
            0,
        );

        //log.debug("scale: {any}, translate: {any}", .{ scale, translate });

        gfx.beginDebugLabel("Render ImGui", gfx_types.Colors.LightCoral);
        defer gfx.endDebugLabel();

        gfx.setRender(.{
            .cull_mode = .none,
            .blend = .{ .enabled = true },
        });

        gfx.setViewport(.{ 0, 0 }, framebuffer_size);
        gfx.bindProgram(program_handle);
        gfx.bindCombinedSampler(
            tex_uniform_handle,
            font_texture_handle,
        );
        gfx.bindUniformBuffer(
            uniform_data_handle,
            uniform_data_buffer_handle,
            0,
        );
        gfx.bindPipelineLayout(pipeline_layout_handle);
        gfx.bindVertexBuffer(vertex_buffer_handle.?, 0);
        gfx.bindIndexBuffer(index_buffer_handle.?, 0);

        const clip_offset: [2]f32 = .{ draw_data.*.DisplayPos.x, draw_data.*.DisplayPos.y };
        const clip_scale: [2]f32 = .{ draw_data.*.FramebufferScale.x, draw_data.*.FramebufferScale.y };

        var global_vertex_offset: u32 = 0;
        var global_index_offset: u32 = 0;
        for (0..@intCast(draw_data.*.CmdListsCount)) |i| {
            const cmd_list = draw_data.*.CmdLists.Data[i];

            for (0..@intCast(cmd_list.*.CmdBuffer.Size)) |j| {
                const cmd = cmd_list.*.CmdBuffer.Data[j];

                const clip_min: [2]f32 = .{
                    @max(0, (cmd.ClipRect.x - clip_offset[0]) * clip_scale[0]),
                    @max(0, (cmd.ClipRect.y - clip_offset[1]) * clip_scale[1]),
                };

                const clip_max: [2]f32 = .{
                    @min(@as(f32, @floatFromInt(framebuffer_size[0])), (cmd.ClipRect.z - clip_offset[0]) * clip_scale[0]),
                    @min(@as(f32, @floatFromInt(framebuffer_size[1])), (cmd.ClipRect.w - clip_offset[1]) * clip_scale[1]),
                };

                if (clip_min[0] >= clip_max[0] or clip_min[1] >= clip_max[1]) {
                    continue;
                }

                gfx.setScissor(
                    .{
                        @as(u32, @intFromFloat(clip_min[0])),
                        @as(u32, @intFromFloat(clip_min[1])),
                    },
                    .{
                        @as(u32, @intFromFloat(clip_max[0] - clip_min[0])),
                        @as(u32, @intFromFloat(clip_max[1] - clip_min[1])),
                    },
                );

                gfx.drawIndexed(
                    cmd.ElemCount,
                    1,
                    cmd.IdxOffset + global_index_offset,
                    @intCast(cmd.VtxOffset + global_vertex_offset),
                    0,
                    if (@sizeOf(c.ImDrawIdx) == 2) .u16 else .u32,
                );
            }

            global_vertex_offset += @intCast(cmd_list.*.VtxBuffer.Size);
            global_index_offset += @intCast(cmd_list.*.IdxBuffer.Size);
        }
    }
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(options: Options) !void {
    main_window_handle = options.window_handle;

    context = c.igCreateContext(null);

    const viewport = c.igGetMainViewport();
    viewport.*.PlatformHandle = @ptrFromInt(@intFromEnum(main_window_handle));

    const io = c.igGetIO_Nil();
    io.*.BackendRendererUserData = null;
    io.*.BackendRendererName = "merlin";
    io.*.BackendFlags = c.ImGuiBackendFlags_RendererHasVtxOffset;
    io.*.BackendFlags = c.ImGuiBackendFlags_HasMouseCursors;
    io.*.BackendFlags = c.ImGuiBackendFlags_HasSetMousePos;
    //io.*.BackendFlags = c.ImGuiBackendFlags_PlatformHasViewports;
    io.*.BackendFlags = c.ImGuiBackendFlags_HasMouseHoveredViewport;

    vert_shader_handle = try gfx.createShaderFromMemory(
        vert_shader_code,
        .{ .debug_name = "ImGui Vertex Shader" },
    );
    errdefer gfx.destroyShader(vert_shader_handle);

    frag_shader_handle = try gfx.createShaderFromMemory(
        frag_shader_code,
        .{ .debug_name = "ImGui Fragment Shader" },
    );
    errdefer gfx.destroyShader(frag_shader_handle);

    program_handle = try gfx.createProgram(
        vert_shader_handle,
        frag_shader_handle,
        .{ .debug_name = "ImGui Program" },
    );
    errdefer gfx.destroyProgram(program_handle);

    const alignment = gfx.uniformAlignment();
    const uniform_data_size = ((@sizeOf(UniformData) + alignment - 1) / alignment) * alignment;
    uniform_data_handle = try gfx.registerUniformName("u_data");
    uniform_data_buffer_handle = try gfx.createBuffer(
        uniform_data_size,
        .{ .uniform = true },
        .host,
        .{
            .debug_name = "ImGui ScaleTranslate Uniform Buffer",
        },
    );
    errdefer gfx.destroyBuffer(uniform_data_buffer_handle);

    var vertex_layout: gfx_types.VertexLayout = .init();
    vertex_layout.add(.position, 2, .f32, false);
    vertex_layout.add(.tex_coord_0, 2, .f32, false);
    vertex_layout.add(.color_0, 4, .u8, true);
    pipeline_layout_handle = try gfx.createPipelineLayout(vertex_layout);
    errdefer gfx.destroyPipelineLayout(pipeline_layout_handle);

    vertex_buffer_handle = null;
    vertex_buffer_size = 0;
    index_buffer_handle = null;
    index_buffer_size = 0;

    _ = c.ImFontAtlas_AddFontDefault(io.*.Fonts, null);

    tex_uniform_handle = try gfx.registerUniformName("s_tex");
    font_texture_handle = try createFontsTexture();
    errdefer gfx.destroyTexture(font_texture_handle);

    try platform.registerWindowFocusCallback(windowFocusCallback);
    errdefer platform.unregisterWindowFocusCallback(windowFocusCallback);

    try platform.registerCursorPositionCallback(cursorPositionCallback);
    errdefer platform.unregisterCursorPositionCallback(cursorPositionCallback);

    try platform.registerMouseButtonCallback(mouseButtonCallback);
    errdefer platform.unregisterMouseButtonCallback(mouseButtonCallback);

    try platform.registerMouseScrollCallback(mouseScrollCallback);
    errdefer platform.unregisterMouseScrollCallback(mouseScrollCallback);

    try platform.registerKeyCallback(keyCallback);
    errdefer platform.unregisterKeyCallback(keyCallback);

    try platform.registerCharCallback(charCallback);
    errdefer platform.unregisterCharCallback(charCallback);
}

pub fn deinit() void {
    platform.unregisterCharCallback(charCallback);
    platform.unregisterKeyCallback(keyCallback);
    platform.unregisterMouseScrollCallback(mouseScrollCallback);
    platform.unregisterMouseButtonCallback(mouseButtonCallback);
    platform.unregisterCursorPositionCallback(cursorPositionCallback);
    platform.unregisterWindowFocusCallback(windowFocusCallback);

    gfx.destroyPipelineLayout(pipeline_layout_handle);
    gfx.destroyBuffer(uniform_data_buffer_handle);
    if (vertex_buffer_handle) |handle| {
        gfx.destroyBuffer(handle);
    }
    if (index_buffer_handle) |handle| {
        gfx.destroyBuffer(handle);
    }
    gfx.destroyTexture(font_texture_handle);
    gfx.destroyShader(vert_shader_handle);
    gfx.destroyShader(frag_shader_handle);
    gfx.destroyProgram(program_handle);
    c.igDestroyContext(context);
}

pub fn update(delta_time: f32) !void {
    const window_size = platform.windowSize(main_window_handle);
    const framebuffer_size = platform.windowFramebufferSize(main_window_handle);

    const io = c.igGetIO_Nil();
    io.*.DisplaySize = c.ImVec2{
        .x = @floatFromInt(window_size[0]),
        .y = @floatFromInt(window_size[1]),
    };
    if (window_size[0] > 0 and window_size[1] > 0) {
        io.*.DisplayFramebufferScale = c.ImVec2{
            .x = @as(f32, @floatFromInt(framebuffer_size[0])) / @as(f32, @floatFromInt(window_size[0])),
            .y = @as(f32, @floatFromInt(framebuffer_size[1])) / @as(f32, @floatFromInt(window_size[1])),
        };
    }
    io.*.DeltaTime = delta_time;

    try updateMonitors();
    try updateMouseCursor();

    // Test window
    c.igNewFrame();
    _ = c.igBegin("TEST", null, 0);
    c.igText("Test");
    _ = c.igButton("Test", .{ .x = 0, .y = 0 });
    c.igEnd();

    var show_demo_window: bool = true;
    c.igShowDemoWindow(&show_demo_window);
    c.igEndFrame();

    c.igRender();

    const draw_data = c.igGetDrawData();
    try draw(draw_data);
}
