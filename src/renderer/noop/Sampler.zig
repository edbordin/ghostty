//! Wrapper for noop samplers.
const Self = @This();

const Texture = @import("Texture.zig");

pub const Options = struct {
    min_filter: Texture.MinFilter,
    mag_filter: Texture.MagFilter,
    wrap_s: Texture.Wrap,
    wrap_t: Texture.Wrap,
};

pub const Error = error{};

opts: Options,

pub fn init(opts: Options) Error!Self {
    return .{ .opts = opts };
}

pub fn deinit(self: Self) void {
    _ = self;
}
