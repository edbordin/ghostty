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
    // Consume clear state from the first step and begin the pass on the
    // swap chain render target. This keeps render sequencing aligned with
    // generic.zig's Frame/RenderPass flow.
    if (self.step_number == 0) {
        var attachment_clear: ?[4]f32 = null;
        if (self.attachments.len > 0) {
            if (self.attachments[0].clear_color) |clear| {
                attachment_clear = clear;
            }
        }

        if (s.uniforms) |uniforms| {
            if (uniforms.bg_color) |bg| {
                self.renderer.api.setPassClearColorFromU8(bg);
            }
        }

        self.renderer.api.beginRenderPass(attachment_clear);
    }

    switch (s.pipeline.kind) {
        .bg_color => {
            if (s.uniforms) |uniforms| {
                self.renderer.api.captureUniformBuffer(uniforms);
            }
            if (s.buffers.len > 1) {
                if (s.buffers[1]) |bg| self.renderer.api.captureBgBuffer(bg);
            }
        },
        .cell_bg => {
            if (s.buffers.len > 1) {
                if (s.buffers[1]) |bg| self.renderer.api.captureBgBuffer(bg);
            }
        },
        .cell_text => {
            var fg: ?D3D11.BufferHandle = null;
            var bg: ?D3D11.BufferHandle = null;
            if (s.buffers.len > 0) fg = s.buffers[0];
            if (s.buffers.len > 1) bg = s.buffers[1];

            var grayscale: ?Texture = null;
            var color: ?Texture = null;
            if (s.textures.len > 0) grayscale = s.textures[0];
            if (s.textures.len > 1) color = s.textures[1];

            self.renderer.api.captureTextStep(.{
                .uniforms = s.uniforms,
                .fg = fg,
                .bg = bg,
                .grayscale = grayscale,
                .color = color,
                .instance_count = s.draw.instance_count,
            });
            self.renderer.api.renderCapturedTextStep();
        },
        else => {},
    }

    self.step_number += 1;
}

pub fn complete(self: *const Self) void {
    _ = self;
}
