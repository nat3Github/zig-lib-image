const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const Image = @import("img2d.zig");

fn cubic_weight(x: f32) f32 {
    const a: f32 = -0.5;
    const abs_x: f32 = @abs(x);
    if (abs_x >= 2.0) {
        return 0.0;
    } else if (abs_x >= 1.0) {
        const abs_x2 = abs_x * abs_x;
        const abs_x3 = abs_x2 * abs_x;
        return a * abs_x3 - 5.0 * a * abs_x2 + 8.0 * a * abs_x - 4.0 * a;
    } else {
        const abs_x2 = abs_x * abs_x;
        const abs_x3 = abs_x2 * abs_x;
        return (a + 2.0) * abs_x3 - (a + 3.0) * abs_x2 + 1.0;
    }
}

inline fn interpolate_point(
    in_data: []const f32,
    n: usize,
    ix_f: f32,
    iy_f: f32,
) f32 {
    const x0 = math.floor(ix_f);
    const y0 = math.floor(iy_f);
    const dx = ix_f - x0;
    const dy = iy_f - y0;
    const x0_i = @as(i64, @intFromFloat(x0));
    const y0_i = @as(i64, @intFromFloat(y0));
    var result: f32 = 0.0;

    var i: i64 = -1;
    while (i <= 2) : (i += 1) {
        const weight_y = cubic_weight(dy - @as(f32, @floatFromInt(i)));
        if (weight_y == 0.0) continue;

        const current_y = y0_i + i;
        const clamped_y = math.clamp(current_y, 0, @as(i64, @intCast(n)) - 1);

        var horizontal_sum: f32 = 0.0;
        var j: i64 = -1;
        while (j <= 2) : (j += 1) {
            const weight_x = cubic_weight(dx - @as(f32, @floatFromInt(j)));
            if (weight_x == 0.0) continue;

            const current_x = x0_i + j;
            const clamped_x = math.clamp(current_x, 0, @as(i64, @intCast(n)) - 1);

            const idx = @as(usize, @intCast(clamped_y)) * n + @as(usize, @intCast(clamped_x));
            horizontal_sum += in_data[idx] * weight_x;
        }
        result += horizontal_sum * weight_y;
    }
    return result;
}
inline fn interpolate_point_angle(
    in_data: []const f32, // in degrees
    n: usize,
    ix_f: f32,
    iy_f: f32,
) f32 {
    const x0 = math.floor(ix_f);
    const y0 = math.floor(iy_f);
    const dx = ix_f - x0;
    const dy = iy_f - y0;
    const x0_i = @as(i64, @intFromFloat(x0));
    const y0_i = @as(i64, @intFromFloat(y0));

    var sum_x: f32 = 0.0;
    var sum_y: f32 = 0.0;

    var i: i64 = -1;
    while (i <= 2) : (i += 1) {
        const weight_y = cubic_weight(dy - @as(f32, @floatFromInt(i)));
        if (weight_y == 0.0) continue;

        const current_y = y0_i + i;
        const clamped_y = math.clamp(current_y, 0, @as(i64, @intCast(n)) - 1);

        var sum_row_x: f32 = 0.0;
        var sum_row_y: f32 = 0.0;

        var j: i64 = -1;
        while (j <= 2) : (j += 1) {
            const weight_x = cubic_weight(dx - @as(f32, @floatFromInt(j)));
            if (weight_x == 0.0) continue;

            const current_x = x0_i + j;
            const clamped_x = math.clamp(current_x, 0, @as(i64, @intCast(n)) - 1);

            const idx = @as(usize, @intCast(clamped_y)) * n + @as(usize, @intCast(clamped_x));
            const angle_deg = in_data[idx];
            const angle_rad = angle_deg * math.pi / 180.0;

            const vec_x = math.cos(angle_rad);
            const vec_y = math.sin(angle_rad);

            sum_row_x += vec_x * weight_x;
            sum_row_y += vec_y * weight_x;
        }

        sum_x += sum_row_x * weight_y;
        sum_y += sum_row_y * weight_y;
    }

    // Convert back to angle
    const interpolated_angle_rad = math.atan2(sum_y, sum_x);
    const interpolated_angle_deg = interpolated_angle_rad * 180.0 / math.pi;

    // Ensure the result is in [0, 360)
    return @mod(interpolated_angle_deg + 360.0, 360.0);
}

pub fn bicubic_interpolate(
    in_data: []const f32,
    out_data: []f32,
    comptime angles: bool,
) void {
    const n = math.sqrt(in_data.len);
    const m = math.sqrt(out_data.len);
    assert(in_data.len == n * n);
    assert(out_data.len == m * m);

    assert(m > 0);
    assert(n >= 2);
    if (m == 0) return;
    if (n < 2) return;

    if (m == 1) {
        const cx1 = (n - 1) / 2;
        const cy1 = (n - 1) / 2;
        const cx2 = cx1 + 1;
        const cy2 = cy1 + 1;
        out_data[0] = (in_data[cy1 * n + cx1] + in_data[cy1 * n + cx2] +
            in_data[cy2 * n + cx1] + in_data[cy2 * n + cx2]) / 4.0;
        return;
    }

    const n_f = @as(f32, @floatFromInt(n));
    const m_f = @as(f32, @floatFromInt(m));
    const scale = n_f / m_f;

    var oy: usize = 0;
    while (oy < m) : (oy += 1) {
        const oy_f = @as(f32, @floatFromInt(oy));
        const iy_f = (oy_f + 0.5) * scale - 0.5;

        var ox: usize = 0;
        while (ox < m) : (ox += 1) {
            const ox_f = @as(f32, @floatFromInt(ox));
            const ix_f = (ox_f + 0.5) * scale - 0.5;
            if (comptime angles) {
                out_data[oy * m + ox] = interpolate_point_angle(in_data, n, ix_f, iy_f);
            } else {
                out_data[oy * m + ox] = interpolate_point(in_data, n, ix_f, iy_f);
            }
        }
    }
}

pub fn bicubic_interpolate_f32(
    in_data: []const f32,
    out_data: []f32,
) void {
    return bicubic_interpolate(in_data, out_data, false);
}

fn test_bicubic_interpolation() !void {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const n: usize = 3;
    const m: usize = 600;

    var in_data: [n * n]f32 = .{
        10.0, 20.0, 15.0,
        12.0, 25.0, 18.0,
        8.0,  22.0, 20.0,
    };
    const Iter = RowMajorIter(f32);
    const it_og = Iter.init(&in_data, n, n);
    const max_og = std.mem.max(f32, &in_data);
    assert(max_og != 0);
    var img_og = try Image.init(alloc, n, n);
    for (0..n) |x| {
        for (0..n) |y| {
            const f = it_og.get_row_major(x, y).*;
            assert(f >= 0);
            const normalized = f / max_og;
            const pixel = Image.Pixel.init_hsv(0.4, 0.7, normalized);
            img_og.set_pixel(x, y, pixel);
        }
    }
    try img_og.write_ppm_to_file("./src/lib/original.ppm");

    const out_data = try alloc.alloc(f32, m * m);
    bicubic_interpolate_f32(&in_data, out_data);

    const it = Iter.init(out_data, m, m);
    const max = std.mem.max(f32, out_data);

    assert(max != 0);
    var img = try Image.init(alloc, m, m);
    for (0..m) |x| {
        for (0..m) |y| {
            const f = it.get_row_major(x, y).*;
            assert(f >= 0);
            const normalized = f / max;
            const pixel = Image.Pixel.init_hsv(0.4, 0.7, normalized);
            img.set_pixel(x, y, pixel);
        }
    }
    try img.write_ppm_to_file("./src/lib/interpolate.ppm");
}

test "test bicubic" {
    try test_bicubic_interpolation();
}

pub fn RowMajorIter(T: type) type {
    return struct {
        slc: []T,
        width: usize,
        height: usize,
        pub fn init(slc: []T, width: usize, height: usize) @This() {
            assert(width * height == slc.len);
            return @This(){
                .slc = slc,
                .width = width,
                .height = height,
            };
        }
        pub fn get_row_major(self: *const @This(), x: usize, y: usize) *T {
            const idx = row_major_index(x, y, self.width);
            return &self.slc[idx];
        }
        pub fn row_major_index(x: usize, y: usize, width: usize) usize {
            return y * width + x;
        }
    };
}
