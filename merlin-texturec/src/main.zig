const std = @import("std");

const c = @import("c.zig").c;

pub fn main() !void {
    //const texture: *c.ktxTexture = undefined;

    //const create_info = std.mem.zeroInit(
    //    c.ktxTextureCreateInfo,
    //    .{
    //        .glInternalformat = c.GL_RGB8,
    //        .baseWidth = 2048,
    //        .baseHeight = 1024,
    //        .baseDepth = 16,
    //        .numDimensions = 3,
    //    },
    //);
}

//pub fn main() !void {
//    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//    defer _ = gpa.deinit();
//
//    const allocator = gpa.allocator();
//
//    const image = try Image.init("statue-1275469_1280.jpg");
//    defer image.deinit();
//
//    const std_out = std.io.getStdOut().writer();
//    try std_out.print("Loaded image with dimensions {d}x{d} and {d} channels\n", .{
//        image.width,
//        image.height,
//        image.channels,
//    });
//
//    const blocks_x = try std.math.divExact(usize, image.width, 4);
//    const blocks_y = try std.math.divExact(usize, image.height, 4);
//
//    const compressed_size = blocks_x * blocks_y * 8;
//    const compressed_data = try allocator.alloc(u8, compressed_size);
//    defer allocator.free(compressed_data);
//
//    for (0..blocks_y) |block_y| {
//        for (0..blocks_x) |block_x| {
//            const src_offset = (block_y * image.width + block_x) * 4;
//            const src_data = image.data[src_offset .. src_offset + 4];
//            const dst_offset = (block_y * blocks_x + block_x) * 8;
//            const dst_data = compressed_data[dst_offset .. dst_offset + 8];
//
//            c.stb_compress_dxt_block(dst_data.ptr, src_data.ptr, 0, 0);
//        }
//    }
//}
//
//const Image = struct {
//    const Self = @This();
//
//    width: usize,
//    height: usize,
//    channels: usize,
//    data: []u8,
//
//    pub fn init(path: []const u8) !Self {
//        var width: c_int = undefined;
//        var height: c_int = undefined;
//        var channels: c_int = undefined;
//        const data = c.stbi_load(
//            path.ptr,
//            &width,
//            &height,
//            &channels,
//            0,
//        );
//
//        if (data == null) {
//            std.log.err("Failed to load image: {s}\n", .{path});
//            return error.ImageError;
//        }
//
//        const size = @as(usize, @intCast(width * height * channels));
//
//        return Image{
//            .width = @intCast(width),
//            .height = @intCast(height),
//            .channels = @intCast(channels),
//            .data = data[0..size],
//        };
//    }
//
//    pub fn deinit(self: *const Self) void {
//        c.stbi_image_free(self.data.ptr);
//    }
//};
//
