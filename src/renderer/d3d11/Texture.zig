//! Wrapper for noop textures.
const Self = @This();
const std = @import("std");

pub const Format = enum {
    red,
    rgba,
    bgra,
};

pub const InternalFormat = enum {
    red,
    rgba,
    srgba,
};

pub const Target = enum {
    @"2D",
    Rectangle,
};

pub const MinFilter = enum {
    nearest,
    linear,
};

pub const MagFilter = enum {
    nearest,
    linear,
};

pub const Wrap = enum {
    clamp_to_edge,
};

pub const Options = struct {
    format: Format,
    internal_format: InternalFormat,
    target: Target,
    min_filter: MinFilter,
    mag_filter: MagFilter,
    wrap_s: Wrap,
    wrap_t: Wrap,
};

pub const Error = error{OutOfMemory};

width: usize,
height: usize,
format: Format,
target: Target,
data: []u8,

pub fn init(
    opts: Options,
    width: usize,
    height: usize,
    data: ?[]const u8,
) Error!Self {
    const bpp = bytesPerPixel(opts.format);
    const total = width * height * bpp;
    var storage = try std.heap.page_allocator.alloc(u8, total);
    @memset(storage, 0);

    if (data) |src| {
        const copy_len = @min(src.len, storage.len);
        @memcpy(storage[0..copy_len], src[0..copy_len]);
    }

    return .{
        .width = width,
        .height = height,
        .format = opts.format,
        .target = opts.target,
        .data = storage,
    };
}

pub fn deinit(self: Self) void {
    std.heap.page_allocator.free(self.data);
}

pub fn replaceRegion(
    self: Self,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: []const u8,
) Error!void {
    if (x >= self.width or y >= self.height) return;
    const bpp = bytesPerPixel(self.format);
    if (bpp == 0) return;

    const copy_w = @min(width, self.width - x);
    const copy_h = @min(height, self.height - y);
    const src_row_bytes = copy_w * bpp;
    const dst_row_pitch = self.width * bpp;

    if (src_row_bytes == 0 or copy_h == 0) return;

    for (0..copy_h) |row| {
        const src_off = row * src_row_bytes;
        const dst_off = (y + row) * dst_row_pitch + x * bpp;
        const src_end = src_off + src_row_bytes;
        if (src_end > data.len) break;
        @memcpy(self.data[dst_off .. dst_off + src_row_bytes], data[src_off..src_end]);
    }
}

pub fn bytesPerPixel(format: Format) usize {
    return switch (format) {
        .red => 1,
        .rgba, .bgra => 4,
    };
}
