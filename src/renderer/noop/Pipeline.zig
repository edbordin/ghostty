//! Wrapper for noop render pipelines.
const Self = @This();

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

stride: usize = 0,
blending_enabled: bool = true,

pub fn init(comptime VertexAttributes: ?type, opts: Options) !Self {
    _ = opts.vertex_fn;
    _ = opts.fragment_fn;
    _ = opts.step_fn;
    return .{
        .stride = if (VertexAttributes) |VA| @sizeOf(VA) else 0,
        .blending_enabled = opts.blending_enabled,
    };
}

pub fn deinit(self: *const Self) void {
    _ = self;
}
