const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;

pub fn squeze_into_range(val: f32, lower: f32, upper: f32) f32 {
    assert(val <= 1);
    assert(val >= 0);
    assert(upper >= lower);
    const dif = upper - lower;
    return val * dif + lower;
}

pub const Pixel = extern struct {
    const This = @This();
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const Transparent = This.init_from_u8_slice(&.{ 0, 0, 0, 0 });
    pub const White = This.init_from_u8_slice(&.{ 255, 255, 255 });
    pub const Gray = This.init_from_u8_slice(&.{ 200, 200, 200 });
    pub const Black = This.init_from_u8_slice(&.{ 0, 0, 0 });
    pub const Red = This.init_from_u8_slice(&.{ 255, 0, 0 });
    pub const Green = This.init_from_u8_slice(&.{ 0, 255, 0 });
    pub const Blue = This.init_from_u8_slice(&.{ 0, 0, 255 });

    pub fn init_from_u8_slice(rgba: []const u8) This {
        assert(rgba.len >= 3);
        assert(rgba.len <= 4);
        var pixel = This{ .r = rgba[0], .g = rgba[1], .b = rgba[2] };
        if (rgba.len == 4) pixel.a = rgba[3];
        return pixel;
    }
    pub fn init_hsv_slice(hsl: []const f32) This {
        assert(hsl.len == 3);
        return init_hsv(hsl[0], hsl[1], hsl[2]);
    }
    pub fn init_hsv(hue: f32, saturation: f32, lightness: f32) This {
        const rgb = hsl_to_rgb(hue, saturation, lightness);
        return init_from_u8_slice(&rgb);
    }
    pub fn to_rgba_arr(self: *const This) [4]u8 {
        var rgba: [4]u8 = undefined;
        rgba[0] = self.r;
        rgba[1] = self.g;
        rgba[2] = self.b;
        rgba[3] = self.a;
        return rgba;
    }
    const clamp = std.math.clamp;
    pub fn multiply_color_aliasing(color: [3]u8, multiplier: f32) [3]u8 {
        var res: [3]u8 = undefined;
        for (color, 0..) |c, i| {
            const f = @as(f32, @floatFromInt(c)) * multiplier;
            res[i] = @intCast(clamp(f, 0, 255));
        }
        return res;
    }

    pub fn grayscale_from_value(value: f32) [3]u8 {
        const gray: u8 = @intFromFloat(value * 255.0);
        return .{ gray, gray, gray };
    }

    pub fn rgb_to_hsl(rgb_color: []const u8) [3]f32 {
        assert(rgb_color.len <= 4);
        // Normalize RGB values
        const r = @as(f32, @floatFromInt(rgb_color[0])) / 255.0;
        const g = @as(f32, @floatFromInt(rgb_color[1])) / 255.0;
        const b = @as(f32, @floatFromInt(rgb_color[2])) / 255.0;

        // Find the maximum and minimum values of RGB
        const c_max = @max(r, @max(g, b));
        const c_min = @min(r, @min(g, b));
        const delta = c_max - c_min;

        // Calculate hue
        const hue: f32 = if (delta == 0.0) 0.0 else if (c_max == r) 60.0 * @mod((g - b) / delta, 6.0) else if (c_max == g) 60.0 * ((b - r) / delta + 2.0) else 60.0 * ((r - g) / delta + 4.0);

        // Ensure hue is within [0, 360)
        const normalized_hue = if (hue < 0.0) hue + 360.0 else hue;

        // Calculate lightness
        const lightness = (c_max + c_min) / 2.0;

        // Calculate saturation
        const saturation = if (delta == 0.0) 0.0 else delta / (1.0 - @abs(2.0 * lightness - 1.0));

        return .{ normalized_hue, saturation, lightness };
    }

    pub fn hsl_to_rgb(hue: f32, saturation: f32, lightness: f32) [3]u8 {
        assert(hue >= 0 and hue <= 1);
        assert(saturation >= 0 and saturation <= 1);
        assert(lightness >= 0);
        assert(lightness <= 1);

        const xhue = hue * 360;
        const chroma = (1.0 - @abs(2.0 * lightness - 1.0)) * saturation;
        const hue_segment = xhue / 60.0;
        const x = chroma * (1.0 - @abs((@mod(hue_segment, 2.0)) - 1.0));

        var r1: f32 = 0;
        var g1: f32 = 0;
        var b1: f32 = 0;

        if (hue_segment < 1.0) {
            r1 = chroma;
            g1 = x;
            b1 = 0.0;
        } else if (hue_segment < 2.0) {
            r1 = x;
            g1 = chroma;
            b1 = 0.0;
        } else if (hue_segment < 3.0) {
            r1 = 0.0;
            g1 = chroma;
            b1 = x;
        } else if (hue_segment < 4.0) {
            r1 = 0.0;
            g1 = x;
            b1 = chroma;
        } else if (hue_segment < 5.0) {
            r1 = x;
            g1 = 0.0;
            b1 = chroma;
        } else {
            r1 = chroma;
            g1 = 0.0;
            b1 = x;
        }

        const m = lightness - chroma / 2.0;
        const r = (r1 + m) * 255.0;
        const g = (g1 + m) * 255.0;
        const b = (b1 + m) * 255.0;

        return .{ @intFromFloat(r), @intFromFloat(g), @intFromFloat(b) };
    }
};

test "test Pixel" {
    const meta_eql = std.meta.eql;
    try expect(meta_eql(Pixel.White, Pixel.init_hsv(1.0, 1.0, 1.0)));
    try expect(meta_eql(Pixel.Black, Pixel.init_hsv(1.0, 1.0, 0)));
    const white_to_hsl = Pixel.rgb_to_hsl(&Pixel.White.to_rgba_arr());
    const white_from_hsl = Pixel.init_hsv_slice(&white_to_hsl);
    try expect(meta_eql(Pixel.White, white_from_hsl));
}

fn size_of_pixel() comptime_int {
    if (comptime @sizeOf(Pixel) != 4) @compileError("size of extern struct Pixel with 4 u8 is expected to be 4");
    return 4;
}

const Image = @This();
const sizeOfPixel = size_of_pixel();
offset_x: usize = 0,
width: usize,
height: usize,
pixel_data: []u8,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Image {
    const pixels = try allocator.alloc(u8, width * height * sizeOfPixel);
    return Image{
        .width = width,
        .height = height,
        .pixel_data = pixels,
    };
}
fn og_width(self: *Image) usize {
    return (self.pixel_data.len / sizeOfPixel) / self.height;
}

pub fn deinit(self: *Image, alloc: Allocator) void {
    alloc.free(self.pixel_data);
}
pub fn sub_img(self: *Image, start: usize, len: usize) Image {
    assert(start + len <= self.width);
    return Image{
        .width = len,
        .height = self.height,
        .offset_x = self.offset_x + start,
        .pixel_data = self.pixel_data,
    };
}
fn px(self: *Image, x: usize, y: usize) *Pixel {
    assert(x < self.width and y < self.height);
    const idx = y * self.og_width() + (x + self.offset_x);
    const pixelbytes = self.pixel_data[idx * sizeOfPixel .. (idx + 1) * sizeOfPixel];
    const ptr: *Pixel = @alignCast(@ptrCast(pixelbytes.ptr));
    return ptr;
}
pub fn set_pixel(self: *Image, x: usize, y: usize, pixel: Pixel) void {
    self.px(x, y).* = pixel;
}
pub fn get_pixel(self: *Image, x: usize, y: usize) Pixel {
    return self.px(x, y).*;
}
pub fn set_column(self: *Image, x: usize, y_0: usize, y_len: usize, pixel: Pixel) void {
    assert(x < self.width);
    assert(y_0 + y_len < self.height);
    for (0..y_len) |i| {
        self.set_pixel(x, y_0 + i, pixel);
    }
}

pub fn set_background_pixels(self: *Image, pixel: Pixel) void {
    for (0..self.height) |y| {
        for (0..self.width) |x| {
            self.set_pixel(x, y, pixel);
        }
    }
}

pub fn export_ppm(self: *Image, writer: anytype) !void {
    try writer.print("P3\n{d} {d}\n255\n", .{ self.width, self.height });
    for (0..self.height) |y| {
        for (self.offset_x..self.offset_x + self.width) |x| {
            const p = self.get_pixel(x, y);
            try writer.print("{d} {d} {d}\n", .{ p.r, p.g, p.b });
        }
    }
}
pub fn write_ppm_to_file(self: *Image, sub_path: []const u8) !void {
    var file = try fs.cwd().createFile(sub_path, .{});
    try self.export_ppm(file.writer());
    file.close();
}

test "test img" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var img = try Image.init(allocator, 4, 4);
    defer img.deinit(allocator);

    for (0..img.height) |y| {
        for (0..img.width) |x| {
            img.set_pixel(x, y, Pixel{ .r = @intCast(x * 34), .g = @intCast(y * 64), .b = 128, .a = 255 });
        }
    }
    // var file = try fs.cwd().createFile("./output/test.ppm", .{});
    // try img.export_ppm(file.writer());
    // file.close();
}
