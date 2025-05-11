const std = @import("std");
const root = @import("root.zig");
const Pixel = root.Pixel;
const Color = [4]u8;
const Image = root;
const math = std.math;

fn fpart(x: f32) f32 {
    return x - @floor(x);
}
fn rfpart(x: f32) f32 {
    return 1.0 - fpart(x);
}

pub const Adapter = struct {
    img: *Image,
    width: u32 = 0,
    height: u32 = 0,
    pub fn init(img: *Image) @This() {
        return @This(){
            .img = img,
            .width = @intCast(img.get_width()),
            .height = @intCast(img.get_height()),
        };
    }
    pub fn putPixel(self: *@This(), x: u32, y: u32, col: Color) void {
        self.img.set_pixel(@intCast(x), @intCast(y), Pixel.init_from_u8_slice(&col));
    }
    pub fn getPixel(self: *@This(), x: u32, y: u32) Color {
        const pix = self.img.get_pixel(@intCast(x), @intCast(y));
        return pix.to_rgba_arr();
    }
};
// const Framebuffer = Adapter;

fn pointToSegmentDistance(px: f32, py: f32, x0: f32, y0: f32, x1: f32, y1: f32) f32 {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const len_sq = dx * dx + dy * dy;

    if (len_sq == 0.0) return @sqrt((px - x0) * (px - x0) + (py - y0) * (py - y0));

    const t = math.clamp(((px - x0) * dx + (py - y0) * dy) / len_sq, 0.0, 1.0);
    const proj_x = x0 + t * dx;
    const proj_y = y0 + t * dy;

    return @sqrt((proj_x - px) * (proj_x - px) + (proj_y - py) * (proj_y - py));
}

fn strokeLineSegmentAA(fb: anytype, p0: [2]f32, p1: [2]f32, width: f32, color: Color) void {
    const hw = width / 2.0;
    const extra = 1.5; // extra pixels for soft AA falloff

    const min_x = @floor(@min(p0[0], p1[0]) - hw - extra);
    const max_x = @ceil(@max(p0[0], p1[0]) + hw + extra);
    const min_y = @floor(@min(p0[1], p1[1]) - hw - extra);
    const max_y = @ceil(@max(p0[1], p1[1]) + hw + extra);

    var y = min_y;
    while (y <= max_y) : (y += 1.0) {
        var x = min_x;
        while (x <= max_x) : (x += 1.0) {
            const dist = pointToSegmentDistance(x + 0.5, y + 0.5, p0[0], p0[1], p1[0], p1[1]);
            const alpha = math.clamp(1.0 - (dist - hw), 0.0, 1.0);
            if (alpha > 0.0) {
                blendPixel(fb, @intFromFloat(x), @intFromFloat(y), color, alpha);
            }
        }
    }
}
fn strokeBezierAA(fb: anytype, p0: [2]f32, p1: [2]f32, p2: [2]f32, p3: [2]f32, width: f32, color: Color) void {
    var prev = p0;
    var t: f32 = 0.0;
    while (t <= 1.0) : (t += 0.02) {
        const x = bezierPoint(t, p0[0], p1[0], p2[0], p3[0]);
        const y = bezierPoint(t, p0[1], p1[1], p2[1], p3[1]);
        strokeLineSegmentAA(fb, prev, .{ x, y }, width, color);
        prev = .{ x, y };
    }
}

fn bezierPoint(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const u = 1.0 - t;
    return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3;
}

fn blendChannel(r: u8, alpha: f32, dst_r: u8) u8 {
    const inv_alpha = 1.0 - alpha;
    return @intFromFloat(math.clamp(@as(f32, @floatFromInt(r)) * alpha + @as(f32, @floatFromInt(dst_r)) * inv_alpha, 0.0, 255.0));
}
fn blendPixel(fb: anytype, x: u32, y: u32, color: Color, alpha: f32) void {
    if (x >= fb.width or y >= fb.height) return;

    const dst = fb.getPixel(x, y);

    fb.putPixel(x, y, Color{
        blendChannel(col_r(color), alpha, col_r(dst)),
        blendChannel(col_g(color), alpha, col_g(dst)),
        blendChannel(col_b(color), alpha, col_b(dst)),
        255,
    });
}
fn col_a(col: Color) u8 {
    return col[3];
}
fn col_b(col: Color) u8 {
    return col[2];
}
fn col_g(col: Color) u8 {
    return col[1];
}
fn col_r(col: Color) u8 {
    return col[0];
}

test "smile" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const wh = 200;
    var img = try Image.init(alloc, wh, wh);
    img.set_background_pixels(.from_hex("#FF00FF"));
    var fb = Adapter.init(&img);

    const black = Color{
        255,
        230,
        0,
        255,
    };
    const lw = 4;

    strokeLineSegmentAA(&fb, .{ 90, 94 }, .{ 102, 106 }, lw, black);
    strokeLineSegmentAA(&fb, .{ 90, 106 }, .{ 102, 94 }, lw, black);
    strokeLineSegmentAA(&fb, .{ 154, 94 }, .{ 166, 106 }, lw, black);
    strokeLineSegmentAA(&fb, .{ 154, 106 }, .{ 166, 94 }, lw, black);

    // Smile
    strokeBezierAA(&fb, .{ 80, 160 }, .{ 110, 190 }, .{ 150, 190 }, .{ 176, 160 }, lw, black);

    var file = try std.fs.cwd().createFile("test/test.ppm", .{});
    try img.export_ppm(file.writer());
    file.close();
    file = try std.fs.cwd().openFile("test/test.ppm", .{});
    defer file.close();
    std.log.warn("done", .{});
}
