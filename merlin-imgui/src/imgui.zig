const std = @import("std");

const gfx = @import("merlin_gfx");
const platform = @import("merlin_platform");
const utils = @import("merlin_utils");
const gfx_types = utils.gfx_types;

pub const c = @import("c.zig").c;
const theme = @import("theme.zig");

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
    theme: theme.CatppuccinTheme = .mocha,
    ui_scale: f32 = 1.25,
};

const VertexConstantData = struct {
    scale: [2]f32,
    translate: [2]f32,
};

const FragmentConstantData = struct {
    srgb: u32,
};

const ViewportData = struct {
    vertex_buffer_handle: ?gfx.BufferHandle = null,
    vertex_buffer_size: u32 = 0,
    index_buffer_handle: ?gfx.BufferHandle = null,
    index_buffer_size: u32 = 0,
    framebuffer_handle: ?gfx.FramebufferHandle = null,
    window_owned: bool = false,
    ignore_window_pos_event_frame: c_int = 0,
    ignore_window_size_event_frame: c_int = 0,
};

// *********************************************************************************************
// Globals
// *********************************************************************************************

var _gpa: std.mem.Allocator = undefined;
var _arena_impl: std.heap.ArenaAllocator = undefined;
var _arena: std.mem.Allocator = undefined;
var _raw_allocator: utils.RawAllocator = undefined;

var _main_window_handle: platform.WindowHandle = undefined;
var _main_framebuffer_handle: gfx.FramebufferHandle = undefined;
var _context: ?*c.ImGuiContext = undefined;
var _font_texture_handle: gfx.TextureHandle = undefined;
var _vert_shader_handle: gfx.ShaderHandle = undefined;
var _frag_shader_handle: gfx.ShaderHandle = undefined;
var _program_handle: gfx.ProgramHandle = undefined;
var _tex_uniform_handle: gfx.NameHandle = undefined;
var _pipeline_layout_handle: gfx.PipelineLayoutHandle = undefined;
var _render_pass_handle: gfx.RenderPassHandle = undefined;

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
        platform.cursorMode(_main_window_handle) == .disabled)
    {
        return;
    }

    const imgui_cursor = c.igGetMouseCursor();
    const platform_io = c.igGetPlatformIO_Nil();

    for (0..@intCast(platform_io.*.Viewports.Size)) |i| {
        const viewport = platform_io.*.Viewports.Data[i];
        const window_handle: platform.WindowHandle = .{ .handle = viewport.*.PlatformHandle.? };
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

fn updateMouseData() !void {
    const io = c.igGetIO_Nil();
    const platform_io = c.igGetPlatformIO_Nil();

    var mouse_viewport_id: c.ImGuiID = 0;
    const mouse_pos_prev = io.*.MousePos;
    for (0..@intCast(platform_io.*.Viewports.Size)) |i| {
        const viewport = platform_io.*.Viewports.Data[i];
        const window_handle: platform.WindowHandle = .{ .handle = viewport.*.PlatformHandle.? };

        const is_window_focused = platform.windowFocused(window_handle);
        if (is_window_focused) {
            if (io.*.WantSetMousePos) {
                platform.setCursorPosition(
                    window_handle,
                    .{
                        mouse_pos_prev.x - viewport.*.Pos.x,
                        mouse_pos_prev.y - viewport.*.Pos.y,
                    },
                );
            }
        }

        if (platform.windowHovered(window_handle))
            mouse_viewport_id = viewport.*.ID;
    }

    if (io.*.BackendFlags & c.ImGuiBackendFlags_HasMouseHoveredViewport != 0) {
        c.ImGuiIO_AddMouseViewportEvent(io, mouse_viewport_id);
    }
}

fn windowFocusCallback(
    window_handle: platform.WindowHandle,
    focused: bool,
) void {
    if (c.igFindViewportByPlatformHandle(window_handle.handle) == null)
        return;

    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddFocusEvent(io, focused);
}

fn cursorPositionCallback(
    window_handle: platform.WindowHandle,
    position: [2]f32,
) void {
    if (c.igFindViewportByPlatformHandle(window_handle.handle) == null)
        return;

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

fn updateKeyModifiers(modifiers: platform.KeyModifier) void {
    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Ctrl, modifiers.control);
    c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Shift, modifiers.shift);
    c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Alt, modifiers.alt);
    c.ImGuiIO_AddKeyEvent(io, c.ImGuiMod_Super, modifiers.super);
}

fn mouseButtonCallback(
    window_handle: platform.WindowHandle,
    btn: platform.MouseButton,
    action: platform.MouseButtonAction,
    modifiers: platform.KeyModifier,
) void {
    if (c.igFindViewportByPlatformHandle(window_handle.handle) == null)
        return;

    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddMouseButtonEvent(io, @intFromEnum(btn), action == .press);
    updateKeyModifiers(modifiers);
}

fn mouseScrollCallback(
    window_handle: platform.WindowHandle,
    x_scroll: f32,
    y_scroll: f32,
) void {
    if (c.igFindViewportByPlatformHandle(window_handle.handle) == null)
        return;

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
    window_handle: platform.WindowHandle,
    key: platform.Key,
    _: i32,
    action: platform.KeyAction,
    modifiers: platform.KeyModifier,
) void {
    if (action != .press and action != .release) return;
    if (c.igFindViewportByPlatformHandle(window_handle.handle) == null)
        return;

    const io = c.igGetIO_Nil();
    const imgui_key = keyToImGuiKey(key);
    c.ImGuiIO_AddKeyEvent(io, imgui_key, action == .press);
    updateKeyModifiers(modifiers);
}

fn charCallback(
    window_handle: platform.WindowHandle,
    character: u32,
) void {
    if (c.igFindViewportByPlatformHandle(window_handle.handle) == null)
        return;

    const io = c.igGetIO_Nil();
    c.ImGuiIO_AddInputCharacter(io, @intCast(character));
}

fn windowCloseCallback(
    window_handle: platform.WindowHandle,
) void {
    const viewport = c.igFindViewportByPlatformHandle(window_handle.handle);
    if (viewport == null)
        return;

    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.*.PlatformUserData));
    if (viewport_data) |data| {
        if (data.window_owned) {
            viewport.*.PlatformRequestClose = true;
        }
    }
}

fn windowPositionCallback(
    window_handle: platform.WindowHandle,
    _: [2]i32,
) void {
    const viewport = c.igFindViewportByPlatformHandle(window_handle.handle);
    if (viewport == null)
        return;

    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.*.PlatformUserData));
    if (viewport_data) |data| {
        if (data.window_owned) {
            const ignore_event = c.igGetFrameCount() <= (data.ignore_window_pos_event_frame + 1);
            if (ignore_event)
                return;

            viewport.*.PlatformRequestMove = true;
        }
    }
}

fn windowSizeCallback(
    window_handle: platform.WindowHandle,
    _: [2]u32,
) void {
    const viewport = c.igFindViewportByPlatformHandle(window_handle.handle);
    if (viewport == null)
        return;

    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.*.PlatformUserData));
    if (viewport_data) |data| {
        if (data.window_owned) {
            const ignore_event = c.igGetFrameCount() <= (data.ignore_window_size_event_frame + 1);
            if (ignore_event)
                return;

            viewport.*.PlatformRequestResize = true;
        }
    }
}

fn draw(
    draw_data: [*c]c.ImDrawData,
    viewport_data: *ViewportData,
    window_handle: platform.WindowHandle,
    render_pass_handle: gfx.RenderPassHandle,
) !void {
    const framebuffer_handle = viewport_data.framebuffer_handle orelse _main_framebuffer_handle;
    if (!try gfx.beginRenderPass(
        framebuffer_handle,
        render_pass_handle,
    )) return;
    defer gfx.endRenderPass();

    if (draw_data.*.TotalVtxCount > 0) {
        const framebuffer_size = platform.windowFramebufferSize(window_handle);
        const vertex_size: u32 = @intCast(@sizeOf(c.ImDrawVert) * draw_data.*.TotalVtxCount);
        const index_size: u32 = @intCast(@sizeOf(c.ImDrawIdx) * draw_data.*.TotalIdxCount);

        if (viewport_data.vertex_buffer_handle == null or viewport_data.vertex_buffer_size < vertex_size) {
            if (viewport_data.vertex_buffer_handle) |handle| {
                gfx.destroyBuffer(handle);
            }
            const buffer_size = vertex_size * 2; // we double the buffer so we have some margin when it grow up
            viewport_data.vertex_buffer_handle = try gfx.createBuffer(
                buffer_size,
                .{ .vertex = true },
                .host,
                .{ .debug_name = "ImGui Vertex Buffer" },
            );
            viewport_data.vertex_buffer_size = buffer_size;
        }

        if (viewport_data.index_buffer_handle == null or viewport_data.index_buffer_size < index_size) {
            if (viewport_data.index_buffer_handle) |handle| {
                gfx.destroyBuffer(handle);
            }
            const buffer_size = index_size * 2; // we double the buffer so we have some margin when it grow up
            viewport_data.index_buffer_handle = try gfx.createBuffer(
                buffer_size,
                .{ .index = true },
                .host,
                .{ .debug_name = "ImGui Index Buffer" },
            );
            viewport_data.index_buffer_size = buffer_size;
        }

        var vertex_offset: u32 = 0;
        var index_offset: u32 = 0;
        for (0..@intCast(draw_data.*.CmdListsCount)) |i| {
            const cmd_list = draw_data.*.CmdLists.Data[i];

            const vertex_count: usize = @intCast(cmd_list.*.VtxBuffer.Size);
            const vertex_cmd_size: usize = @intCast(@sizeOf(c.ImDrawVert) * vertex_count);
            const vertex_cmd_data = cmd_list.*.VtxBuffer.Data[0..vertex_count];
            try gfx.updateBufferFromMemory(
                viewport_data.vertex_buffer_handle.?,
                @ptrCast(vertex_cmd_data),
                vertex_offset,
            );
            vertex_offset += @intCast(vertex_cmd_size);

            const index_count: usize = @intCast(cmd_list.*.IdxBuffer.Size);
            const index_cmd_size: usize = @intCast(@sizeOf(c.ImDrawIdx) * index_count);
            const index_cmd_data = cmd_list.*.IdxBuffer.Data[0..index_count];
            try gfx.updateBufferFromMemory(
                viewport_data.index_buffer_handle.?,
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
        const vertex_constant_data = VertexConstantData{
            .scale = scale,
            .translate = translate,
        };
        const vertex_constant_data_ptr: [*]const u8 = @ptrCast(&vertex_constant_data);

        const fragment_constant_data = FragmentConstantData{
            .srgb = 1,
        };
        const fragment_constant_data_ptr: [*]const u8 = @ptrCast(&fragment_constant_data);

        gfx.beginDebugLabel("Render ImGui", gfx_types.Colors.LightCoral);
        defer gfx.endDebugLabel();

        gfx.setRender(.{
            .cull_mode = .none,
            .blend = .{ .enabled = true },
        });

        gfx.setViewport(.{ 0, 0 }, framebuffer_size);
        gfx.pushConstants(
            .vertex,
            0,
            vertex_constant_data_ptr[0..@sizeOf(VertexConstantData)],
        );
        gfx.pushConstants(
            .fragment,
            64,
            fragment_constant_data_ptr[0..@sizeOf(FragmentConstantData)],
        );
        gfx.bindProgram(_program_handle);
        gfx.bindCombinedSampler(
            _tex_uniform_handle,
            _font_texture_handle,
        );
        gfx.bindPipelineLayout(_pipeline_layout_handle);
        gfx.bindVertexBuffer(viewport_data.vertex_buffer_handle.?, 0);
        gfx.bindIndexBuffer(viewport_data.index_buffer_handle.?, 0);

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
                    @min(
                        @as(f32, @floatFromInt(framebuffer_size[0])),
                        (cmd.ClipRect.z - clip_offset[0]) * clip_scale[0],
                    ),
                    @min(
                        @as(f32, @floatFromInt(framebuffer_size[1])),
                        (cmd.ClipRect.w - clip_offset[1]) * clip_scale[1],
                    ),
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

fn setClipboardTextFn(_: ?*c.ImGuiContext, clipboard_text: [*c]const u8) callconv(.c) void {
    platform.setClipboardText(
        _main_window_handle,
        clipboard_text[0..std.mem.len(clipboard_text)],
    ) catch |err| {
        log.err("Failed to set clipboard text: {}", .{err});
    };
}

fn getClipboardTextFn(_: ?*c.ImGuiContext) callconv(.c) [*c]const u8 {
    const clipboard_text = platform.clipboardText(_main_window_handle);
    if (clipboard_text) |text_ptr| {
        return text_ptr.ptr;
    } else {
        return null;
    }
}

fn createWindow(viewport: ?*c.ImGuiViewport) callconv(.c) void {
    const window_handle = platform.createWindow(.{
        .title = "No Title Yet",
        .width = @intFromFloat(viewport.?.Size.x),
        .height = @intFromFloat(viewport.?.Size.y),
        .visible = false,
        .focused = false,
        .decorated = viewport.?.Flags & c.ImGuiViewportFlags_NoDecoration == 0,
        .floating = viewport.?.Flags & c.ImGuiViewportFlags_TopMost != 0,
    }) catch |err| {
        log.err("Failed to create window: {}", .{err});
        return;
    };

    platform.setWindowPosition(window_handle, .{
        @intFromFloat(viewport.?.Pos.x),
        @intFromFloat(viewport.?.Pos.y),
    });

    const framebuffer_handle = gfx.createFramebuffer(
        window_handle,
        _render_pass_handle,
    ) catch |err| {
        log.err("Failed to create framebuffer: {}", .{err});
        return;
    };

    const viewport_data = _gpa.create(ViewportData) catch |err| {
        log.err("Failed to create viewport data: {}", .{err});
        return;
    };
    errdefer _gpa.destroy(viewport_data);

    viewport_data.* = .{
        .window_owned = true,
        .framebuffer_handle = framebuffer_handle,
    };

    viewport.?.PlatformHandle = window_handle.handle;
    viewport.?.PlatformUserData = @ptrCast(viewport_data);
}

fn destroyWindow(viewport: ?*c.ImGuiViewport) callconv(.c) void {
    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.?.PlatformUserData));
    if (viewport_data) |data| {
        if (data.framebuffer_handle) |handle| {
            gfx.destroyFramebuffer(handle);
        }
        if (data.vertex_buffer_handle) |handle| {
            gfx.destroyBuffer(handle);
        }
        if (data.index_buffer_handle) |handle| {
            gfx.destroyBuffer(handle);
        }
        if (data.window_owned) {
            const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
            platform.destroyWindow(window_handle);
        }
        _gpa.destroy(data);
    }
    viewport.?.PlatformHandle = null;
    viewport.?.PlatformUserData = null;
}

fn showWindow(viewport: ?*c.ImGuiViewport) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    platform.showWindow(window_handle);
}

fn getWindowPosition(viewport: ?*c.ImGuiViewport) callconv(.c) c.ImVec2 {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    const position = platform.windowPosition(window_handle);
    return c.ImVec2{
        .x = @floatFromInt(position[0]),
        .y = @floatFromInt(position[1]),
    };
}

fn setWindowPosition(viewport: ?*c.ImGuiViewport, pos: c.ImVec2) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.?.PlatformUserData));
    viewport_data.?.ignore_window_pos_event_frame = c.igGetFrameCount();
    platform.setWindowPosition(window_handle, .{
        @intFromFloat(pos.x),
        @intFromFloat(pos.y),
    });
}

fn getWindowSize(viewport: ?*c.ImGuiViewport) callconv(.c) c.ImVec2 {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    const size = platform.windowSize(window_handle);
    return c.ImVec2{
        .x = @floatFromInt(size[0]),
        .y = @floatFromInt(size[1]),
    };
}

fn setWindowSize(viewport: ?*c.ImGuiViewport, size: c.ImVec2) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.?.PlatformUserData));
    viewport_data.?.ignore_window_size_event_frame = c.igGetFrameCount();
    platform.setWindowSize(window_handle, .{
        @intFromFloat(size.x),
        @intFromFloat(size.y),
    });
}

fn getWindowFocus(viewport: ?*c.ImGuiViewport) callconv(.c) bool {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    return platform.windowFocused(window_handle);
}

fn setWindowFocus(viewport: ?*c.ImGuiViewport) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    platform.setWindowFocus(window_handle);
}

fn setWindowTitle(viewport: ?*c.ImGuiViewport, title: [*c]const u8) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    platform.setWindowTitle(window_handle, title[0..std.mem.len(title)]) catch |err| {
        log.err("Failed to set window title: {}", .{err});
    };
}

fn getWindowMinimized(viewport: ?*c.ImGuiViewport) callconv(.c) bool {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    return platform.windowMinimized(window_handle);
}

fn setWindowAlpha(viewport: ?*c.ImGuiViewport, alpha: f32) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    platform.setWindowAlpha(window_handle, alpha);
}

fn renderWindow(viewport: ?*c.ImGuiViewport, _: ?*anyopaque) callconv(.c) void {
    const window_handle: platform.WindowHandle = .{ .handle = viewport.?.PlatformHandle.? };
    const viewport_data: ?*ViewportData = @ptrCast(@alignCast(viewport.?.PlatformUserData));
    if (viewport_data) |data| {
        if (data.window_owned) {
            draw(
                viewport.?.DrawData,
                viewport_data.?,
                window_handle,
                _render_pass_handle,
            ) catch |err| {
                log.err("Failed to render ImGui: {}", .{err});
            };
        }
    }
}

const MemoryAlignment = 16; // Should be fine on x86_64 and ARM64
fn memoryAllocFn(size: usize, _: ?*anyopaque) callconv(.c) ?*anyopaque {
    return _raw_allocator.allocate(size, MemoryAlignment);
}

fn memoryFreeFn(ptr: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    _raw_allocator.free(@ptrCast(ptr));
}

// *********************************************************************************************
// Public API
// *********************************************************************************************

pub fn init(
    allocator: std.mem.Allocator,
    render_pass_handle: gfx.RenderPassHandle,
    framebuffer_handle: gfx.FramebufferHandle,
    options: Options,
) !void {
    _gpa = allocator;
    _raw_allocator = .init(allocator);

    _arena_impl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer _arena_impl.deinit();
    _arena = _arena_impl.allocator();

    _main_window_handle = options.window_handle;
    _main_framebuffer_handle = framebuffer_handle;
    _render_pass_handle = render_pass_handle;

    c.igSetAllocatorFunctions(memoryAllocFn, memoryFreeFn, null);

    _context = c.igCreateContext(null);

    const io = c.igGetIO_Nil();
    io.*.BackendRendererUserData = null;
    io.*.BackendRendererName = "merlin";

    io.*.BackendFlags |= c.ImGuiBackendFlags_RendererHasVtxOffset;
    io.*.BackendFlags |= c.ImGuiBackendFlags_RendererHasViewports;
    io.*.BackendFlags |= c.ImGuiBackendFlags_HasMouseCursors;
    io.*.BackendFlags |= c.ImGuiBackendFlags_HasSetMousePos;
    io.*.BackendFlags |= c.ImGuiBackendFlags_HasMouseHoveredViewport;
    if (platform.nativeWindowHandleType() != .wayland) {
        io.*.BackendFlags |= c.ImGuiBackendFlags_PlatformHasViewports;
    }

    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_ViewportsEnable;

    const viewport = c.igGetMainViewport();
    viewport.*.PlatformHandle = _main_window_handle.handle;

    const viewport_data = _gpa.create(ViewportData) catch |err| {
        log.err("Failed to create viewport data: {}", .{err});
        return;
    };
    viewport_data.* = .{};
    viewport.*.PlatformUserData = @ptrCast(viewport_data);

    _vert_shader_handle = try gfx.createShaderFromMemory(
        vert_shader_code,
        .{ .debug_name = "ImGui Vertex Shader" },
    );
    errdefer gfx.destroyShader(_vert_shader_handle);

    _frag_shader_handle = try gfx.createShaderFromMemory(
        frag_shader_code,
        .{ .debug_name = "ImGui Fragment Shader" },
    );
    errdefer gfx.destroyShader(_frag_shader_handle);

    _program_handle = try gfx.createProgram(
        _vert_shader_handle,
        _frag_shader_handle,
        .{ .debug_name = "ImGui Program" },
    );
    errdefer gfx.destroyProgram(_program_handle);

    var vertex_layout: gfx_types.VertexLayout = .init();
    vertex_layout.add(.position, 2, .f32, false);
    vertex_layout.add(.tex_coord_0, 2, .f32, false);
    vertex_layout.add(.color_0, 4, .u8, true);
    _pipeline_layout_handle = try gfx.createPipelineLayout(vertex_layout);
    errdefer gfx.destroyPipelineLayout(_pipeline_layout_handle);

    theme.setup(options.theme, options.ui_scale);

    _tex_uniform_handle = gfx.nameHandle("s_tex");
    _font_texture_handle = try createFontsTexture();
    errdefer gfx.destroyTexture(_font_texture_handle);

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

    try platform.registerWindowCloseCallback(windowCloseCallback);
    errdefer platform.unregisterWindowCloseCallback(windowCloseCallback);

    try platform.registerWindowPositionCallback(windowPositionCallback);
    errdefer platform.unregisterWindowPositionCallback(windowPositionCallback);

    try platform.registerWindowSizeCallback(windowSizeCallback);
    errdefer platform.unregisterWindowSizeCallback(windowSizeCallback);

    const platform_io = c.igGetPlatformIO_Nil();
    platform_io.*.Platform_SetClipboardTextFn = setClipboardTextFn;
    platform_io.*.Platform_GetClipboardTextFn = getClipboardTextFn;
    platform_io.*.Platform_CreateWindow = createWindow;
    platform_io.*.Platform_DestroyWindow = destroyWindow;
    platform_io.*.Platform_ShowWindow = showWindow;
    platform_io.*.Platform_GetWindowPos = getWindowPosition;
    platform_io.*.Platform_SetWindowPos = setWindowPosition;
    platform_io.*.Platform_GetWindowSize = getWindowSize;
    platform_io.*.Platform_SetWindowSize = setWindowSize;
    platform_io.*.Platform_GetWindowFocus = getWindowFocus;
    platform_io.*.Platform_SetWindowFocus = setWindowFocus;
    platform_io.*.Platform_SetWindowTitle = setWindowTitle;
    platform_io.*.Platform_GetWindowMinimized = getWindowMinimized;
    platform_io.*.Platform_SetWindowAlpha = setWindowAlpha;
    platform_io.*.Platform_RenderWindow = renderWindow;
}

pub fn deinit() void {
    platform.unregisterWindowSizeCallback(windowSizeCallback);
    platform.unregisterWindowPositionCallback(windowPositionCallback);
    platform.unregisterWindowCloseCallback(windowCloseCallback);
    platform.unregisterCharCallback(charCallback);
    platform.unregisterKeyCallback(keyCallback);
    platform.unregisterMouseScrollCallback(mouseScrollCallback);
    platform.unregisterMouseButtonCallback(mouseButtonCallback);
    platform.unregisterCursorPositionCallback(cursorPositionCallback);
    platform.unregisterWindowFocusCallback(windowFocusCallback);

    c.igDestroyPlatformWindows();

    gfx.destroyPipelineLayout(_pipeline_layout_handle);
    gfx.destroyTexture(_font_texture_handle);
    gfx.destroyShader(_vert_shader_handle);
    gfx.destroyShader(_frag_shader_handle);
    gfx.destroyProgram(_program_handle);
    c.igDestroyContext(_context);

    _arena_impl.deinit();
}

pub fn beginFrame(delta_time: f32) void {
    const window_size = platform.windowSize(_main_window_handle);
    const framebuffer_size = platform.windowFramebufferSize(_main_window_handle);

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

    updateMonitors() catch |err| {
        log.err("Failed to update monitors: {}", .{err});
    };

    updateMouseCursor() catch |err| {
        log.err("Failed to update mouse cursor: {}", .{err});
    };

    updateMouseData() catch |err| {
        log.err("Failed to update mouse data: {}", .{err});
    };

    c.igNewFrame();
}

pub fn endFrame() void {
    _ = _arena_impl.reset(.retain_capacity);

    c.igEndFrame();

    c.igRender();

    const draw_data = c.igGetDrawData();

    const viewport = c.igGetMainViewport();
    const viewport_data: *ViewportData = @ptrCast(@alignCast(viewport.*.PlatformUserData));
    draw(draw_data, viewport_data, _main_window_handle, _render_pass_handle) catch |err| {
        log.err("Failed to render ImGui: {}", .{err});
    };

    const io = c.igGetIO_Nil();
    if (io.*.ConfigFlags & c.ImGuiConfigFlags_ViewportsEnable != 0) {
        c.igUpdatePlatformWindows();
        c.igRenderPlatformWindowsDefault(
            null,
            null,
        );
    }
}
