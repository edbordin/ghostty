//! Wrapper for noop render passes.
const Self = @This();

const D3D11 = @import("../D3D11.zig");
const Renderer = @import("../generic.zig").Renderer(D3D11);
const api = @import("api.zig");
const Pipeline = @import("Pipeline.zig");
const Sampler = @import("Sampler.zig");
const Texture = @import("Texture.zig");
const Target = @import("Target.zig");

pub const Options = struct {
    renderer: *Renderer,
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
    uniforms: ?D3D11.BufferHandle = null,
    buffers: []const ?D3D11.BufferHandle = &.{},
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
renderer: *Renderer,
step_number: usize = 0,

pub fn begin(opts: Options) Self {
    return .{
        .attachments = opts.attachments,
        .renderer = opts.renderer,
    };
}

pub fn step(self: *Self, s: Step) void {
    // This is the first rendering logic slice for the D3D11 backend:
    // consume pass clear state and the frame bg color from uniforms so
    // present() uses renderer-driven colors instead of a fixed constant.
    if (self.step_number == 0) {
        if (self.attachments.len > 0) {
            if (self.attachments[0].clear_color) |clear| {
                self.renderer.api.setPassClearColor(clear);
            }
        }

        if (s.uniforms) |uniforms| {
            if (uniforms.bg_color) |bg| {
                self.renderer.api.setPassClearColorFromU8(bg);
            }
        }
    }

    self.step_number += 1;
}

pub fn complete(self: *const Self) void {
    _ = self;
}
