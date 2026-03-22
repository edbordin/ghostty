//! Wrapper for noop textures.
const Self = @This();

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

pub const Error = error{};

width: usize,
height: usize,
format: Format,
target: Target,

pub fn init(
    opts: Options,
    width: usize,
    height: usize,
    data: ?[]const u8,
) Error!Self {
    _ = data;
    return .{
        .width = width,
        .height = height,
        .format = opts.format,
        .target = opts.target,
    };
}

pub fn deinit(self: Self) void {
    _ = self;
}

pub fn replaceRegion(
    self: Self,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: []const u8,
) Error!void {
    _ = self;
    _ = x;
    _ = y;
    _ = width;
    _ = height;
    _ = data;
}
