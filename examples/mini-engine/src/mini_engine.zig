const std = @import("std");

pub const assets = @import("merlin_assets");
pub const gfx = @import("merlin_gfx");
pub const imgui = @import("merlin_imgui");
pub const platform = @import("merlin_platform");
pub const utils = @import("merlin_utils");
pub const zmath = @import("zmath");

pub const InitContext = struct {
    gpa_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    window_handle: platform.WindowHandle,
    framebuffer_handle: gfx.FramebufferHandle,
};

pub fn Context(comptime T: type) type {
    return struct {
        gpa_allocator: std.mem.Allocator,
        arena_allocator: std.mem.Allocator,
        window_handle: platform.WindowHandle,
        framebuffer_handle: gfx.FramebufferHandle,
        delta_time: f32,
        total_time: f32,
        data: T,
    };
}

const AnsiColorRed = "\x1b[31m";
const AnsiColorYellow = "\x1b[33m";
const AnsiColorWhite = "\x1b[37m";
const AnsiColorGray = "\x1b[90m";
const AnsiColorLightGray = "\x1b[37;1m";
const AnsiColorReset = "\x1b[0m";

pub fn customLog(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    const color = comptime switch (level) {
        .info => AnsiColorWhite,
        .warn => AnsiColorYellow,
        .err => AnsiColorRed,
        .debug => AnsiColorGray,
    };

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(
            color ++ level_txt ++ prefix2 ++ format ++ AnsiColorReset ++ "\n",
            args,
        ) catch return;
        bw.flush() catch return;
    }
}

fn getAssetPath(allocator: std.mem.Allocator, asset_name: []const u8) ![]const u8 {
    const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
    defer allocator.free(exe_path);

    return try std.fs.path.join(allocator, &[_][]const u8{
        exe_path,
        std.mem.bytesAsSlice(u8, "assets"),
        asset_name,
    });
}

pub fn loadShader(allocator: std.mem.Allocator, filename: []const u8) !gfx.ShaderHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    return try gfx.createShader(file.reader().any(), .{
        .debug_name = filename,
    });
}

pub fn loadTexture(allocator: std.mem.Allocator, filename: []const u8) !gfx.TextureHandle {
    const path = try getAssetPath(allocator, filename);
    defer allocator.free(path);

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();

    return try gfx.createTextureFromKTX(
        file.reader().any(),
        @intCast(stat.size),
        .{
            .debug_name = filename,
        },
    );
}

pub fn run_engine(
    comptime T: type,
    name: []const u8,
    init_callback: fn (InitContext) anyerror!T,
    deinit_callback: fn (*Context(T)) void,
    update_callback: fn (*Context(T)) anyerror!void,
) !void {
    // Allocators
    var gpa = std.heap.GeneralPurposeAllocator(.{
        //.verbose_log = true,
    }){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const gpa_allocator = gpa.allocator();
    const arena_allocator = arena.allocator();

    // Platform
    try platform.init(
        gpa_allocator,
        .{ .type = .glfw },
    );
    defer platform.deinit();

    // Window
    const window_handle = try platform.createWindow(.{
        .width = 1280,
        .height = 720,
        .title = name,
    });
    defer platform.destroyWindow(window_handle);

    // Graphics
    try gfx.init(
        gpa_allocator,
        .{
            .renderer_type = .vulkan,
            .window_handle = window_handle,
            .enable_vulkan_debug = true,
        },
    );
    defer gfx.deinit();

    // Framebuffer
    const framebuffer_handle = try gfx.createFramebuffer(
        window_handle,
        // main_render_pass_handle,
    );
    defer gfx.destroyFramebuffer(framebuffer_handle);

    // Assets system
    try assets.init(gpa_allocator);
    defer assets.deinit();

    // ImGUI
    try imgui.init(
        gpa_allocator,
        // ui_render_pass_handle,
        framebuffer_handle,
        .{
            .window_handle = window_handle,
        },
    );
    defer imgui.deinit();

    const data = try init_callback(.{
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .window_handle = window_handle,
        .framebuffer_handle = framebuffer_handle,
    });

    var context = Context(T){
        .gpa_allocator = gpa_allocator,
        .arena_allocator = arena_allocator,
        .window_handle = window_handle,
        .framebuffer_handle = framebuffer_handle,
        .delta_time = 0.0,
        .total_time = 0.0,
        .data = data,
    };
    defer deinit_callback(&context);

    const start_time = std.time.microTimestamp();
    var last_current_time = start_time;

    while (!platform.shouldCloseWindow(window_handle)) {
        defer _ = arena.reset(.retain_capacity);

        platform.pollEvents();

        const current_time = std.time.microTimestamp();
        const delta_time = @as(f32, @floatFromInt(current_time - last_current_time)) / 1_000_000.0;
        last_current_time = current_time;

        context.delta_time = delta_time;
        context.total_time += delta_time;

        const result = gfx.beginFrame() catch |err| {
            std.log.err("Failed to begin frame: {}", .{err});
            continue;
        };
        if (!result) continue;

        try update_callback(&context);

        gfx.endFrame() catch |err| {
            std.log.err("Failed to end frame: {}", .{err});
        };
    }
}
