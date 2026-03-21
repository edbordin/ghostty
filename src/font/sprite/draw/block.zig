//! Block Elements | U+2580...U+259F
//! https://en.wikipedia.org/wiki/Block_Elements
//!
//! â–€â–â–‚â–ƒâ–„â–…â–†â–‡â–ˆâ–‰â–Šâ–‹â–Œâ–â–Žâ–
//! â–â–‘â–’â–“â–”â–•â––â–—â–˜â–™â–šâ–›â–œâ–â–žâ–Ÿ
//!

const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");
const Shade = common.Shade;
const Quads = common.Quads;
const Alignment = common.Alignment;
const fill = common.fill;

const font = @import("../../main.zig");

// Utility names for common fractions
const one_eighth: f64 = 0.125;
const one_quarter: f64 = 0.25;
const one_third: f64 = (1.0 / 3.0);
const three_eighths: f64 = 0.375;
const half: f64 = 0.5;
const five_eighths: f64 = 0.625;
const two_thirds: f64 = (2.0 / 3.0);
const three_quarters: f64 = 0.75;
const seven_eighths: f64 = 0.875;

pub fn draw2580_259F(
    cp: u32,
    canvas: *font.sprite.Canvas,
    width: u32,
    height: u32,
    metrics: font.Metrics,
) !void {
    _ = width;
    _ = height;

    switch (cp) {
        // 'â–€' UPPER HALF BLOCK
        0x2580 => block(metrics, canvas, .upper, 1, half),
        // 'â–' LOWER ONE EIGHTH BLOCK
        0x2581 => block(metrics, canvas, .lower, 1, one_eighth),
        // 'â–‚' LOWER ONE QUARTER BLOCK
        0x2582 => block(metrics, canvas, .lower, 1, one_quarter),
        // 'â–ƒ' LOWER THREE EIGHTHS BLOCK
        0x2583 => block(metrics, canvas, .lower, 1, three_eighths),
        // 'â–„' LOWER HALF BLOCK
        0x2584 => block(metrics, canvas, .lower, 1, half),
        // 'â–…' LOWER FIVE EIGHTHS BLOCK
        0x2585 => block(metrics, canvas, .lower, 1, five_eighths),
        // 'â–†' LOWER THREE QUARTERS BLOCK
        0x2586 => block(metrics, canvas, .lower, 1, three_quarters),
        // 'â–‡' LOWER SEVEN EIGHTHS BLOCK
        0x2587 => block(metrics, canvas, .lower, 1, seven_eighths),
        // 'â–ˆ' FULL BLOCK
        0x2588 => fullBlockShade(metrics, canvas, .on),
        // 'â–‰' LEFT SEVEN EIGHTHS BLOCK
        0x2589 => block(metrics, canvas, .left, seven_eighths, 1),
        // 'â–Š' LEFT THREE QUARTERS BLOCK
        0x258a => block(metrics, canvas, .left, three_quarters, 1),
        // 'â–‹' LEFT FIVE EIGHTHS BLOCK
        0x258b => block(metrics, canvas, .left, five_eighths, 1),
        // 'â–Œ' LEFT HALF BLOCK
        0x258c => block(metrics, canvas, .left, half, 1),
        // 'â–' LEFT THREE EIGHTHS BLOCK
        0x258d => block(metrics, canvas, .left, three_eighths, 1),
        // 'â–Ž' LEFT ONE QUARTER BLOCK
        0x258e => block(metrics, canvas, .left, one_quarter, 1),
        // 'â–' LEFT ONE EIGHTH BLOCK
        0x258f => block(metrics, canvas, .left, one_eighth, 1),

        // 'â–' RIGHT HALF BLOCK
        0x2590 => block(metrics, canvas, .right, half, 1),
        // 'â–‘'
        0x2591 => fullBlockShade(metrics, canvas, .light),
        // 'â–’'
        0x2592 => fullBlockShade(metrics, canvas, .medium),
        // 'â–“'
        0x2593 => fullBlockShade(metrics, canvas, .dark),
        // 'â–”' UPPER ONE EIGHTH BLOCK
        0x2594 => block(metrics, canvas, .upper, 1, one_eighth),
        // 'â–•' RIGHT ONE EIGHTH BLOCK
        0x2595 => block(metrics, canvas, .right, one_eighth, 1),
        // 'â––'
        0x2596 => quadrant(metrics, canvas, .{ .bl = true }),
        // 'â–—'
        0x2597 => quadrant(metrics, canvas, .{ .br = true }),
        // 'â–˜'
        0x2598 => quadrant(metrics, canvas, .{ .tl = true }),
        // 'â–™'
        0x2599 => quadrant(metrics, canvas, .{ .tl = true, .bl = true, .br = true }),
        // 'â–š'
        0x259a => quadrant(metrics, canvas, .{ .tl = true, .br = true }),
        // 'â–›'
        0x259b => quadrant(metrics, canvas, .{ .tl = true, .tr = true, .bl = true }),
        // 'â–œ'
        0x259c => quadrant(metrics, canvas, .{ .tl = true, .tr = true, .br = true }),
        // 'â–'
        0x259d => quadrant(metrics, canvas, .{ .tr = true }),
        // 'â–ž'
        0x259e => quadrant(metrics, canvas, .{ .tr = true, .bl = true }),
        // 'â–Ÿ'
        0x259f => quadrant(metrics, canvas, .{ .tr = true, .bl = true, .br = true }),

        else => unreachable,
    }
}

pub fn block(
    metrics: font.Metrics,
    canvas: *font.sprite.Canvas,
    comptime alignment: Alignment,
    comptime width: f64,
    comptime height: f64,
) void {
    blockShade(metrics, canvas, alignment, width, height, .on);
}

pub fn blockShade(
    metrics: font.Metrics,
    canvas: *font.sprite.Canvas,
    comptime alignment: Alignment,
    comptime width: f64,
    comptime height: f64,
    comptime shade: Shade,
) void {
    const float_width: f64 = @floatFromInt(metrics.cell_width);
    const float_height: f64 = @floatFromInt(metrics.cell_height);

    const w: u32 = @intFromFloat(@round(float_width * width));
    const h: u32 = @intFromFloat(@round(float_height * height));

    const x = switch (alignment.horizontal) {
        .left => 0,
        .right => metrics.cell_width - w,
        .center => (metrics.cell_width - w) / 2,
    };
    const y = switch (alignment.vertical) {
        .top => 0,
        .bottom => metrics.cell_height - h,
        .middle => (metrics.cell_height - h) / 2,
    };

    canvas.rect(.{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = @intCast(w),
        .height = @intCast(h),
    }, @as(font.sprite.Color, @enumFromInt(@intFromEnum(shade))));
}

pub fn fullBlockShade(
    metrics: font.Metrics,
    canvas: *font.sprite.Canvas,
    shade: Shade,
) void {
    canvas.box(
        0,
        0,
        @intCast(metrics.cell_width),
        @intCast(metrics.cell_height),
        @as(font.sprite.Color, @enumFromInt(@intFromEnum(shade))),
    );
}

fn quadrant(
    metrics: font.Metrics,
    canvas: *font.sprite.Canvas,
    comptime quads: Quads,
) void {
    if (quads.tl) fill(metrics, canvas, .zero, .half, .zero, .half);
    if (quads.tr) fill(metrics, canvas, .half, .full, .zero, .half);
    if (quads.bl) fill(metrics, canvas, .zero, .half, .half, .full);
    if (quads.br) fill(metrics, canvas, .half, .full, .half, .full);
}
