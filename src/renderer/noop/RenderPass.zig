//! Wrapper for noop render passes.
const Self = @This();

const Noop = @import("../Noop.zig");
const api = @import("api.zig");
const Pipeline = @import("Pipeline.zig");
const Sampler = @import("Sampler.zig");
const Texture = @import("Texture.zig");
const Target = @import("Target.zig");

pub const Options = struct {
    attachments: []const Attachment,

    pub const Attachment = struct {
        target: union(enum) {
            texture: Texture,
            target: Target,
        },
        clear_color: ?[4]f32 = null,
    };
};

pub const Step = struct {
    pipeline: Pipeline,
    uniforms: ?Noop.BufferHandle = null,
    buffers: []const ?Noop.BufferHandle = &.{},
    textures: []const ?Texture = &.{},
    samplers: []const ?Sampler = &.{},
    draw: Draw,

    pub const Draw = struct {
        type: api.Primitive,
        vertex_count: usize,
        instance_count: usize = 1,
    };
};

attachments: []const Options.Attachment,

pub fn begin(opts: Options) Self {
    return .{ .attachments = opts.attachments };
}

pub fn step(self: *Self, s: Step) void {
    _ = self;
    _ = s;
}

pub fn complete(self: *const Self) void {
    _ = self;
}
