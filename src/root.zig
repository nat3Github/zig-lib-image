const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const expect = std.testing.expect;
const Allocator = std.mem.Allocator;
pub const draw = @import("drawing2.zig");

pub fn squeze_into_range(val: f32, lower: f32, upper: f32) f32 {
    assert(val <= 1);
    assert(val >= 0);
    assert(upper >= lower);
    const dif = upper - lower;
    return val * dif + lower;
}
pub const Pixel = @import("pixel.zig").Pixel;
pub const Blending = @import("blending.zig");
pub const BlendMode = Blending.BlendMode;
pub const AlphaCompositing = Blending.AlphaCompositing;

pub const Image = @This();
const sizeOfPixel = @import("pixel.zig").size_of_pixel();
__intern_offset_x: usize = 0,
__intern_width: usize,
__static_width: usize,
_row_major_px: []u8,
__alloc: ?Allocator = null,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Image {
    assert(height > 0);
    const pixels = try allocator.alloc(u8, width * height * sizeOfPixel);
    return Image{
        .__static_width = width,
        .__intern_width = width,
        ._row_major_px = pixels,
        .__alloc = allocator,
    };
}
/// NOTE: dont call resize on subimages
pub fn resize(self: *Image, width: usize, height: usize) !void {
    if (self.get_height() == height and self.get_width() == width) return;
    self._row_major_px = try self.__alloc.?.realloc(self._row_major_px, width * height * sizeOfPixel);
    self.__static_width = width;
    self.__intern_width = width;
    self.__intern_offset_x = 0;
}
pub fn get_width(self: *const Image) usize {
    return self.__intern_width;
}
pub fn get_height(img: *const Image) usize {
    return (img._row_major_px.len / sizeOfPixel) / img.__static_width;
}
pub fn get_pixel_data(img: *const Image) []const u8 {
    return img._row_major_px;
}

pub fn deinit(self: *Image) void {
    const alloc = self.__alloc.?;
    alloc.free(self._row_major_px);
}
/// NOTE: the Image return is a reference to the original Image, you can mutate it but the memory is owned by the original image, its just a "view" into an Image
/// so dont resize the Image!
pub fn sub_img(
    img: *Image,
    x_offset: usize,
    width: usize,
    y_offset: usize,
    height: usize,
) Image {
    assert(img.__intern_offset_x + x_offset + width <= img.get_width());
    assert(y_offset + height <= img.get_height());
    const ret = Image{
        .__static_width = img.__static_width,
        .__intern_width = width,
        .__intern_offset_x = img.__intern_offset_x + x_offset,
        ._row_major_px = img.get_y_slice(y_offset, height),
        .__alloc = null,
    };
    return ret;
}
fn get_y_slice(
    self: *Image,
    y_offset: usize,
    y_len: usize,
) []u8 {
    return self.get_row_major_pixel_slice(y_offset * self.__static_width, (y_offset + y_len) * self.__static_width);
}
fn get_row_major_pixel_slice(self: *Image, start: usize, end: usize) []u8 {
    assert(start <= end);
    return self._row_major_px[start * sizeOfPixel .. end * sizeOfPixel];
}

fn px(self: *Image, x: usize, y: usize) *Pixel {
    assert(x < self.get_width() and y < self.get_height());
    const idx = y * self.__static_width + (x + self.__intern_offset_x);
    const pixelbytes = self._row_major_px[idx * sizeOfPixel .. (idx + 1) * sizeOfPixel];
    const ptr: *Pixel = @alignCast(@ptrCast(pixelbytes.ptr));
    return ptr;
}
pub fn set_pixel(self: *Image, x: usize, y: usize, pixel: Pixel) void {
    self.px(x, y).* = pixel;
}
pub fn get_pixel(self: *const Image, x: usize, y: usize) Pixel {
    return px(@constCast(self), x, y).*;
}
pub fn set_column(self: *Image, x: usize, y_0: usize, y_len: usize, pixel: Pixel) void {
    assert(x < self.get_width);
    assert(y_0 + y_len < self.get_height);
    for (0..y_len) |i| {
        self.set_pixel(x, y_0 + i, pixel);
    }
}

pub fn set_background_pixels(self: *Image, pixel: Pixel) void {
    for (0..self.get_height()) |y| {
        for (0..self.get_width()) |x| {
            self.set_pixel(x, y, pixel);
        }
    }
}
/// NOTE: will be extremly slow when using unbuffered writers!
pub fn export_ppm(self: *Image, writer: anytype) !void {
    try writer.print("P3\n{d} {d}\n255\n", .{ self.get_width(), self.get_height() });
    for (0..self.get_height()) |y| {
        for (0..self.get_width()) |x| {
            const p = self.get_pixel(x, y);
            const grid = 30;

            var alphaPixel = Pixel.Magenta;
            if (((x / grid) % 2 == 0 and (y / grid) % 2 == 0) or
                ((x / grid) % 2 == 1 and (y / grid) % 2 == 1))
            {
                alphaPixel = Pixel.White;
            } else {
                alphaPixel = Pixel.Magenta;
            }

            const blend = alphaPixel.blend(p, BlendMode.override, AlphaCompositing.premultiplied);
            try writer.print("{d} {d} {d}\n", .{
                blend.r,
                blend.g,
                blend.b,
            });
        }
    }
}
pub fn write_ppm_to_file(self: *Image, sub_path: []const u8) !void {
    var file = try fs.cwd().createFile(sub_path, .{});
    var buf = std.io.bufferedWriter(file.writer());
    try self.export_ppm(buf.writer());
    try buf.flush();
    file.close();
}
pub fn from_ppm_P3(alloc: Allocator, file: std.fs.File) !@This() {
    var sr = file.reader();
    var buf: [1024]u8 = undefined;
    var line: []const u8 = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    if (!std.mem.eql(u8, "P3", line)) return error.InvalidFormat;
    line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    line = std.mem.trim(u8, line, " ");

    if (line[0] == '#') {
        line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    }

    var tokenizer = std.mem.tokenizeAny(u8, line, " ");
    const width = try std.fmt.parseInt(usize, tokenizer.next() orelse return error.InvalidFormat, 10);
    const height = try std.fmt.parseInt(usize, tokenizer.next() orelse return error.InvalidFormat, 10);

    line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    line = std.mem.trim(u8, line, " ");
    tokenizer = std.mem.tokenizeAny(u8, line, " ");
    const max_val = try std.fmt.parseInt(usize, tokenizer.next() orelse return error.InvalidFormat, 10);
    if (max_val != 255) return error.UnsupportedMaxVal;

    var img = try Image.init(alloc, width, height);

    for (0..height) |y| {
        for (0..width) |x| {
            line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
            tokenizer = std.mem.tokenizeAny(u8, line, " ");
            const r = try std.fmt.parseInt(u8, tokenizer.next() orelse return error.InvalidFormat, 10);
            const g = try std.fmt.parseInt(u8, tokenizer.next() orelse return error.InvalidFormat, 10);
            const b = try std.fmt.parseInt(u8, tokenizer.next() orelse return error.InvalidFormat, 10);
            img.set_pixel(x, y, .init_rgb(r, g, b));
        }
    }
    return img;
}
pub fn from_ppm_P6(alloc: Allocator, file: std.fs.File) !@This() {
    var sr = file.reader();
    var buf: [1024]u8 = undefined;
    var line: []const u8 = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    if (!std.mem.eql(u8, "P6", line)) return error.InvalidFormat;
    line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    line = std.mem.trim(u8, line, " ");

    if (line[0] == '#') {
        line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    }
    var tokenizer = std.mem.tokenizeAny(u8, line, " ");
    const width = try std.fmt.parseInt(usize, tokenizer.next() orelse return error.InvalidFormat, 10);
    const height = try std.fmt.parseInt(usize, tokenizer.next() orelse return error.InvalidFormat, 10);

    line = try sr.readUntilDelimiterOrEof(&buf, '\n') orelse return error.InvalidFormat;
    line = std.mem.trim(u8, line, " ");
    tokenizer = std.mem.tokenizeAny(u8, line, " ");
    const max_val = try std.fmt.parseInt(usize, tokenizer.next() orelse return error.InvalidFormat, 10);
    if (max_val != 255) return error.UnsupportedMaxVal;

    var img = try Image.init(alloc, width, height);

    for (0..height) |y| {
        for (0..width) |x| {
            const r = try sr.readByte();
            const g = try sr.readByte();
            const b = try sr.readByte();
            img.set_pixel(x, y, .init_rgb(r, g, b));
        }
    }
    return img;
}
pub fn eql(self: *const @This(), img: *const @This()) bool {
    if (self.get_height() != img.get_height()) return false;
    if (self.get_width() != img.get_width()) return false;
    for (0..self.get_width()) |x| {
        for (0..self.get_height()) |y| {
            if (!self.get_pixel(x, y).eql(img.get_pixel(x, y))) return false;
        }
    }
    return true;
}
test "kkk" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var img = try Image.init(alloc, 4, 4);
    const si = img.sub_img(0, img.get_width(), 0, img.get_height());
    try expect(si.eql(&img));
    const si2 = img.sub_img(0, img.get_width(), 0, 2);
    try expect(si2.get_height() == 2);
}

test "test img" {
    if (true) return;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var img = try Image.init(alloc, 4, 4);

    for (0..img.get_height()) |y| {
        for (0..img.get_width()) |x| {
            img.set_pixel(x, y, Pixel{ .r = @intCast(x * 34), .g = @intCast(y * 64), .b = 128, .a = 255 });
        }
    }

    var file = try fs.cwd().createFile("test/test.ppm", .{});
    try img.export_ppm(file.writer());
    file.close();
    file = try fs.cwd().openFile("test/test.ppm", .{});
    defer file.close();
    var img2 = try Image.from_ppm_P3(alloc, file);
    try expect(img.eql(&img2));
}

test "test all" {
    _ = .{
        Pixel,
        Blending,
        draw,
    };
}
