const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const Image = root.Image;
const Pixel = Image.Pixel;

// Utility to normalize u8 to f32
fn norm(x: u8) f32 {
    const xf: f32 = @floatFromInt(x);
    return xf / 255;
}

// Utility to denormalize f32 to u8
fn denorm(x: f32) u8 {
    return @intFromFloat(@min(@max(x, 0), 1) * 255);
}

// Blend helpers (common code)
fn blend_channel(base: u8, chan: u8, fnc: fn (f32, f32) f32) u8 {
    return denorm(fnc(norm(base), norm(chan)));
}

pub fn blend(
    px1: Pixel,
    px2: Pixel,
    comptime blending: BlendMode,
    comptime alpha_compositing: AlphaCompositing,
) Pixel {
    const name = @tagName(blending);
    const fnc = @field(blend_mode_fn, name);
    var px2c = px2;
    px2c.r = blend_channel(px1.r, px2.r, fnc);
    px2c.g = blend_channel(px1.g, px2.g, fnc);
    px2c.b = blend_channel(px1.b, px2.b, fnc);
    return switch (alpha_compositing) {
        .premultiplied => blend_premultiplied(
            px2c,
            px1,
        ),
        .non_premultiplied => blend_non_premultiplied(
            px2c,
            px1,
        ),
    };
}

pub const AlphaCompositing = enum {
    premultiplied,
    non_premultiplied,
};
/// Blends two premultiplied RGBA pixels.
/// Each color component and alpha are u8 (0..=255).
pub fn blend_premultiplied(
    src: Pixel,
    dst: Pixel,
) Pixel {
    const inv_src_a: u16 = @intCast(255 - src.a);
    const out_r = @as(u16, @intCast(src.r)) + ((@as(u16, @intCast(dst.r)) * inv_src_a + 127) / 255);
    const out_g = @as(u16, @intCast(src.g)) + ((@as(u16, @intCast(dst.g)) * inv_src_a + 127) / 255);
    const out_b = @as(u16, @intCast(src.b)) + ((@as(u16, @intCast(dst.b)) * inv_src_a + 127) / 255);
    const out_a = @as(u16, @intCast(src.a)) + ((@as(u16, @intCast(dst.a)) * inv_src_a + 127) / 255);
    return Pixel{
        .r = @intCast(@min(out_r, 255)),
        .g = @intCast(@min(out_g, 255)),
        .b = @intCast(@min(out_b, 255)),
        .a = @intCast(@min(out_a, 255)),
    };
}

test "test premultiplied" {
    // fn test_blend_premultiplied_fully_opaque() {
    const src0 = Pixel.init_rgba(100, 150, 200, 255); // Fully opaque
    const dst0 = Pixel.init_rgba(50, 50, 50, 255);
    try expect(Pixel.eql(blend_premultiplied(src0, dst0), src0));

    // fn test_blend_premultiplied_fully_transparent() {
    const src1 = Pixel.init_rgba(0, 0, 0, 0); // Fully transparent
    const dst1 = Pixel.init_rgba(50, 50, 50, 255);
    try expect(Pixel.eql(blend_premultiplied(src1, dst1), dst1));

    // fn test_blend_premultiplied_half_alpha() {
    const src2 = Pixel.init_rgba(128, 128, 0, 128); // Half transparent
    const dst2 = Pixel.init_rgba(0, 0, 128, 255);
    const result2 = blend_premultiplied(src2, dst2);
    try expect(Pixel.eql(result2, Pixel.init_rgba(128, 128, 64, 255)));
}
/// Blends two non-premultiplied RGBA pixels.
/// Each color component and alpha are u8 (0..=255).
pub fn blend_non_premultiplied(
    src: Pixel,
    dst: Pixel,
) Pixel {
    const src_af = norm(src.a);
    const dst_af = norm(dst.a);
    const amf = dst_af * (1.0 - src_af);
    const out_af = src_af + amf;
    if (out_af == 0.0) {
        return Pixel{
            .r = 0,
            .a = 0,
            .b = 0,
            .g = 0,
        };
    }
    const out_r = (@as(f32, @floatFromInt(src.r)) * src_af + @as(f32, @floatFromInt(dst.r)) * amf) / out_af;
    const out_g = (@as(f32, @floatFromInt(src.g)) * src_af + @as(f32, @floatFromInt(dst.g)) * amf) / out_af;
    const out_b = (@as(f32, @floatFromInt(src.b)) * src_af + @as(f32, @floatFromInt(dst.b)) * amf) / out_af;

    return Pixel{
        .r = @intFromFloat(@round(out_r)),
        .g = @intFromFloat(@round(out_g)),
        .b = @intFromFloat(@round(out_b)),
        .a = @intFromFloat(@round(out_af * 255.0)),
    };
}
test "blend non premultiplied" {
    // fn test_blend_non_premultiplied_fully_opaque() {
    const src0 = Pixel.init_rgba(255, 0, 0, 255); // Red, fully opaque
    const dst0 = Pixel.init_rgba(0, 255, 0, 255); // Green
    try expect(Pixel.eql(blend_non_premultiplied(src0, dst0), Pixel.init_rgba(255, 0, 0, 255))); // src wins

    // fn test_blend_non_premultiplied_fully_transparent() {
    const src1 = Pixel.init_rgba(0, 0, 255, 0); // Blue, fully transparent
    const dst1 = Pixel.init_rgba(0, 255, 0, 255); // Green
    try expect(Pixel.eql(blend_non_premultiplied(src1, dst1), Pixel.init_rgba(0, 255, 0, 255))); // dst wins

    // fn test_blend_non_premultiplied_half_alpha() {
    const src2 = Pixel.init_rgba(255, 0, 0, 128); // Half-transparent red
    const dst2 = Pixel.init_rgba(0, 0, 255, 255); // Blue background
    const result2 = blend_non_premultiplied(src2, dst2);
    try expect(Pixel.eql(result2, Pixel.init_rgba(128, 0, 127, 255)));
}

pub fn blend_runtime(px: Pixel, wpx: Pixel, blendmode: BlendMode, alpha_comp: AlphaCompositing) Pixel {
    return switch (blendmode) {
        .override => px.blend(wpx, .override, alpha_comp),
        .darken => px.blend(wpx, .darken, alpha_comp),
        .lighten => px.blend(wpx, .lighten, alpha_comp),
        .screen => px.blend(wpx, .screen, alpha_comp),
        .linear_burn => px.blend(wpx, .linear_burn, alpha_comp),
        .color_burn => px.blend(wpx, .color_burn, alpha_comp),
        .multiply => px.blend(wpx, .multiply, alpha_comp),
        .color_dodge => px.blend(wpx, .color_dodge, alpha_comp),
        .linear_dodge => px.blend(wpx, .linear_dodge, alpha_comp),
        .blend_overlay => px.blend(wpx, .blend_overlay, alpha_comp),
        .soft_light => px.blend(wpx, .soft_light, alpha_comp),
        .hard_light => px.blend(wpx, .hard_light, alpha_comp),
        .difference => px.blend(wpx, .difference, alpha_comp),
        .exclusion => px.blend(wpx, .exclusion, alpha_comp),
    };
}

pub const BlendMode = enum(u8) {
    /// Normal blend (top pixel simply overrides bottom pixel)
    override = 0,
    /// Multiply blend (multiplies base and blend channels)
    multiply = 1,
    /// Soft Light blend (gentle contrast depending on blend)
    soft_light = 2,
    /// Hard Light blend (overlay but driven by blend)
    hard_light = 3,
    /// Darken blend (takes the darker pixel per channel)
    darken = 4,
    /// Lighten blend (takes the lighter pixel per channel)
    lighten = 5,
    /// Screen blend (inverse multiply for brighter look)
    screen = 6,
    /// Linear Burn blend (adds base and blend and subtracts 1.0)
    linear_burn = 7,
    /// Color Burn blend (darkens bottom depending on blend)
    color_burn = 8,
    /// Color Dodge blend (brightens based on blend color)
    color_dodge = 9,
    /// Linear Dodge (Add) blend (simply adds pixel values)
    linear_dodge = 10,
    /// Overlay blend (multiply or screen depending on base)
    blend_overlay = 11,
    /// Difference blend (absolute difference between pixels)
    difference = 12,
    /// Exclusion blend (lower contrast difference)
    exclusion = 13,
};

pub const blend_mode_fn = struct {
    /// Normal blend (top pixel simply overrides bottom pixel)
    pub fn override(_: f32, b: f32) f32 {
        return b;
    }
    /// Darken blend (takes the darker pixel per channel)
    pub fn darken(a: f32, b: f32) f32 {
        return @min(a, b);
    }
    /// Lighten blend (takes the lighter pixel per channel)
    pub fn lighten(a: f32, b: f32) f32 {
        return @max(a, b);
    }
    /// Screen blend (inverse multiply for brighter look)
    pub fn screen(a: f32, b: f32) f32 {
        return 1.0 - (1.0 - a) * (1.0 - b);
    }
    /// Linear Burn blend (adds base and blend and subtracts 1.0)
    pub fn linear_burn(a: f32, b: f32) f32 {
        return @max(a + b - 1.0, 0.0);
    }
    /// Color Burn blend (darkens bottom depending on blend)
    pub fn color_burn(a: f32, b: f32) f32 {
        if (b == 0) return 0.0 else return 1.0 - @min(1.0, (1.0 - a) / b);
    }
    /// Multiply blend (multiplies base and blend channels)
    pub fn multiply(a: f32, b: f32) f32 {
        return a * b;
    }
    /// Color Dodge blend (brightens based on blend color)
    pub fn color_dodge(a: f32, b: f32) f32 {
        if (b == 1.0) return 1.0 else return @min(a / (1.0 - b), 1.0);
    }
    /// Linear Dodge (Add) blend (simply adds pixel values)
    pub fn linear_dodge(a: f32, b: f32) f32 {
        return @min(a + b, 1.0);
    }
    /// Overlay blend (multiply or screen depending on base)
    pub fn blend_overlay(a: f32, b: f32) f32 {
        if (a < 0.5) return 2.0 * a * b else return 1.0 - 2.0 * (1.0 - a) * (1.0 - b);
    }
    /// Soft Light blend (gentle contrast depending on blend)
    pub fn soft_light(a: f32, b: f32) f32 {
        return (1.0 - 2.0 * b) * a * a + 2.0 * b * a;
    }
    /// Hard Light blend (overlay but driven by blend)
    pub fn hard_light(a: f32, b: f32) f32 {
        if (b < 0.5) return 2.0 * a * b else return 1.0 - 2.0 * (1.0 - a) * (1.0 - b);
    }
    /// Difference blend (absolute difference between pixels)
    pub fn difference(a: f32, b: f32) f32 {
        return @abs(a - b);
    }
    /// Exclusion blend (lower contrast difference)
    pub fn exclusion(a: f32, b: f32) f32 {
        return a + b - 2.0 * a * b;
    }
};

test "test blend" {
    const px1 = Pixel.Blue;
    const px2 = Pixel.Red;
    inline for (@typeInfo(BlendMode).@"enum".fields, 0..) |_, i| {
        _ = blend(px1, px2, @enumFromInt(i), .premultiplied);
    }
    inline for (@typeInfo(BlendMode).@"enum".fields, 0..) |_, i| {
        _ = blend(px1, px2, @enumFromInt(i), .non_premultiplied);
    }
}

test "test generate test images" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const winter = try std.fs.cwd().openFile("test/winter.ppm", .{});
    const goose = try std.fs.cwd().openFile("test/goose.ppm", .{});
    const img1 = try Image.from_ppm_P6(alloc, winter);
    const img2 = try Image.from_ppm_P6(alloc, goose);

    const mwidth = @min(img1.width, img2.width);
    const mheight = @min(img1.height, img2.height);
    var img = try Image.init(alloc, mwidth, mheight);
    inline for (@typeInfo(BlendMode).@"enum".fields, 0..) |_, i| {
        const bm: BlendMode = @enumFromInt(i);
        const am: AlphaCompositing = .non_premultiplied;
        for (0..img.height) |y| {
            for (0..img.width) |x| {
                const px1 = img1.get_pixel(x, y);
                const px2 = img2.get_pixel(x, y);
                const px = blend(px1, px2, bm, am);
                img.set_pixel(x, y, px);
            }
        }
        var f = try std.fs.cwd().createFile(std.fmt.comptimePrint("test/{s}/{s}.ppm", .{
            @tagName(am),
            @tagName(bm),
        }), .{});
        defer f.close();
        try img.export_ppm(f.writer());
    }
    std.log.warn("hello wkkkk orlk", .{});
}
