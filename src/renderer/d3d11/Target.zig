//! Represents a noop render target.
const Self = @This();

const Texture = @import("Texture.zig");

pub const Options = struct {
    width: usize,
    height: usize,
    internal_format: Texture.InternalFormat,
};

width: usize,
height: usize,
internal_format: Texture.InternalFormat,

pub fn init(opts: Options) !Self {
    return .{
        .width = opts.width,
        .height = opts.height,
        .internal_format = opts.internal_format,
    };
}

pub fn deinit(self: *Self) void {
    self.* = undefined;
}
