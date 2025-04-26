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
const Pixel = @import("pixel.zig");
const Image = @This();
const sizeOfPixel = Pixel.size_of_pixel();
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
