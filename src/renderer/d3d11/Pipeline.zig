//! Wrapper for noop render pipelines.
const Self = @This();
const std = @import("std");

pub const Options = struct {
    vertex_fn: [:0]const u8,
    fragment_fn: [:0]const u8,
    step_fn: StepFunction = .per_vertex,
    blending_enabled: bool = true,

    pub const StepFunction = enum {
        constant,
        per_vertex,
        per_instance,
    };
};

pub const Kind = enum {
    unknown,
    bg_color,
    cell_bg,
    cell_text,
    image,
    bg_image,
    postprocess,
};

stride: usize = 0,
blending_enabled: bool = true,
kind: Kind = .unknown,

pub fn init(comptime VertexAttributes: ?type, opts: Options) !Self {
    _ = opts.step_fn;
    return .{
        .stride = if (VertexAttributes) |VA| @sizeOf(VA) else 0,
        .blending_enabled = opts.blending_enabled,
        .kind = classifyPipeline(opts.vertex_fn, opts.fragment_fn),
    };
}

pub fn deinit(self: *const Self) void {
    _ = self;
}

fn classifyPipeline(
    vertex_fn: [:0]const u8,
    fragment_fn: [:0]const u8,
) Kind {
    if (std.mem.eql(u8, fragment_fn, "bg_color_fragment")) return .bg_color;
    if (std.mem.eql(u8, fragment_fn, "cell_bg_fragment")) return .cell_bg;
    if (std.mem.eql(u8, fragment_fn, "cell_text_fragment")) return .cell_text;
    if (std.mem.eql(u8, fragment_fn, "image_fragment")) return .image;
    if (std.mem.eql(u8, fragment_fn, "bg_image_fragment")) return .bg_image;
    if (std.mem.eql(u8, vertex_fn, "full_screen_vertex")) return .postprocess;
    return .unknown;
}
