const std = @import("std");
const fs = std.fs;
const assert = std.debug.assert;
const expect = std.testing.expect;

pub const Pixel = extern struct {
    pub const Blending = @import("blending.zig");
    pub const BlendMode = Blending.BlendMode;
    pub const AlphaCompositing = Blending.AlphaCompositing;
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const Transparent = init_rgba(0, 0, 0, 0);
    pub const White = init_rgb(255, 255, 255);
    pub const Gray = init_rgb(200, 200, 200);
    pub const Black = init_rgb(0, 0, 0);
    pub const Red = init_rgb(255, 0, 0);
    pub const Green = init_rgb(0, 255, 0);
    pub const Blue = init_rgb(0, 0, 255);

    pub fn init_rgba(r: u8, g: u8, b: u8, a: u8) Pixel {
        return .init_from_rgba_tuple(.{ r, g, b, a });
    }
    pub fn init_rgb(r: u8, g: u8, b: u8) Pixel {
        return .init_from_rgb_tuple(.{ r, g, b });
    }
    pub fn from_hex(comptime hex: []const u8) Pixel {
        const xrgba = comptime hexToRgb(hex) catch {
            @compileError("failed to convert rgba from hex code");
        };
        return Pixel.init_from_u8_slice(&xrgba);
    }
    pub fn convert_hex(hex: []const u8) !Pixel {
        const xrgba = try hexToRgb(hex);
        return Pixel.init_from_u8_slice(&xrgba);
    }
    pub inline fn hexToRgb(hex: []const u8) ![4]u8 {
        var xrgba: [4]u8 = .{ 0, 0, 0, 255 };
        if (hex.len == 6) {
            for (xrgba[0..3], 0..) |_, i| {
                const start = i * 2;
                const slice = hex[start .. start + 2];
                const value = try std.fmt.parseInt(u8, slice, 16);
                xrgba[i] = value;
            }
            return xrgba;
        }
        if (hex.len == 7 and hex[0] == '#') {
            const hex1 = hex[1..];
            for (xrgba[0..3], 0..) |_, i| {
                const start = i * 2;
                const slice = hex1[start .. start + 2];
                const value = try std.fmt.parseInt(u8, slice, 16);
                xrgba[i] = value;
            }
            return xrgba;
        }
        return error.FailedToParseHexColor;
    }
    pub fn eql(a: Pixel, b: Pixel) bool {
        return std.mem.eql(u8, &a.to_rgba_arr(), &b.to_rgba_arr());
    }
    pub fn blend(
        base: Pixel,
        other: Pixel,
        comptime blend_mode: BlendMode,
        comptime alpha_compositing: AlphaCompositing,
    ) Pixel {
        return Blending.blend(base, other, blend_mode, alpha_compositing);
    }
    pub fn blend_runtime(
        base: Pixel,
        other: Pixel,
        blend_mode: BlendMode,
        comptime alpha_compositing: AlphaCompositing,
    ) Pixel {
        return Blending.blend_runtime(base, other, blend_mode, alpha_compositing);
    }
    pub fn init_from_u8_slice(rgba: []const u8) Pixel {
        assert(rgba.len >= 3);
        assert(rgba.len <= 4);
        var pixel = Pixel{ .r = rgba[0], .g = rgba[1], .b = rgba[2] };
        if (rgba.len == 4) pixel.a = rgba[3];
        return pixel;
    }
    pub fn init_from_rgb_tuple(rgb: struct { u8, u8, u8 }) Pixel {
        const r, const g, const b = rgb;
        return Pixel{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn init_from_rgba_tuple(rgba: struct { u8, u8, u8, u8 }) Pixel {
        const r, const g, const b, const a = rgba;
        return Pixel{ .r = r, .g = g, .b = b, .a = a };
    }
    pub fn init_hsv_slice(hsl: []const f32) Pixel {
        assert(hsl.len == 3);
        return init_hsv(hsl[0], hsl[1], hsl[2]);
    }
    pub fn init_hsv(hue: f32, saturation: f32, lightness: f32) Pixel {
        const rgb = hsl_to_rgb(hue, saturation, lightness);
        return init_from_u8_slice(&rgb);
    }
    pub fn to_rgba_arr(self: *const Pixel) [4]u8 {
        var rgba: [4]u8 = undefined;
        rgba[0] = self.r;
        rgba[1] = self.g;
        rgba[2] = self.b;
        rgba[3] = self.a;
        return rgba;
    }
    pub fn to_rgba_tuple(self: *const Pixel) struct { u8, u8, u8, u8 } {
        return .{
            self.r,
            self.g,
            self.b,
            self.a,
        };
    }
    pub fn to_rgb_tuple(self: *const Pixel) struct { u8, u8, u8 } {
        return .{
            self.r,
            self.g,
            self.b,
        };
    }
    pub fn multiply_color_aliasing(color: [3]u8, multiplier: f32) [3]u8 {
        const clamp = std.math.clamp;
        var res: [3]u8 = undefined;
        for (color, 0..) |c, i| {
            const f = @as(f32, @floatFromInt(c)) * multiplier;
            res[i] = @intCast(clamp(f, 0, 255));
        }
        return res;
    }
    fn to_bw(color: struct { u8, u8, u8 }, contrast: f32) u8 {
        const r, const b, const g = color;
        const luminance: f32 = @as(f32, @floatFromInt(r)) * 0.299 + @as(f32, @floatFromInt(g)) * 0.587 + @as(f32, @floatFromInt(b)) * 0.114;
        var normalized = luminance / 255.0;
        normalized = (normalized - 0.5) * contrast + 0.5;
        normalized = std.math.clamp(normalized, 0.0, 1.0);
        const bw: u8 = @intFromFloat(normalized * 255.0);
        return bw;
    }
    pub fn to_gray_pixel(self: *const Pixel) Pixel {
        const bw = to_bw(self.to_rgb_tuple(), 1);
        return Pixel{
            .r = bw,
            .g = bw,
            .b = bw,
            .a = self.a,
        };
    }

    pub fn grayscale_from_value(value: f32) [3]u8 {
        const gray: u8 = @intFromFloat(value * 255.0);
        return .{ gray, gray, gray };
    }

    pub fn rgb_to_hsl(rgb_color: []const u8) [3]f32 {
        assert(rgb_color.len <= 4);
        const r = @as(f32, @floatFromInt(rgb_color[0])) / 255.0;
        const g = @as(f32, @floatFromInt(rgb_color[1])) / 255.0;
        const b = @as(f32, @floatFromInt(rgb_color[2])) / 255.0;

        const c_max = @max(r, @max(g, b));
        const c_min = @min(r, @min(g, b));
        const delta = c_max - c_min;

        const hue: f32 = if (delta == 0.0) 0.0 else if (c_max == r) 60.0 * @mod((g - b) / delta, 6.0) else if (c_max == g) 60.0 * ((b - r) / delta + 2.0) else 60.0 * ((r - g) / delta + 4.0);

        const normalized_hue = if (hue < 0.0) hue + 360.0 else hue;
        const lightness = (c_max + c_min) / 2.0;
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
pub fn size_of_pixel() comptime_int {
    if (comptime @sizeOf(Pixel) != 4) @compileError("size of extern struct Pixel with 4 u8 is expected to be 4");
    return 4;
}
