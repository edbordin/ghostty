//! Wrapper for noop frame handling.
const Self = @This();

const Renderer = @import("../generic.zig").Renderer(Noop);
const Noop = @import("../Noop.zig");
const Target = @import("Target.zig");
const RenderPass = @import("RenderPass.zig");

pub const Options = struct {};

renderer: *Renderer,
target: *Target,

pub fn begin(
    opts: Options,
    renderer: *Renderer,
    target: *Target,
) !Self {
    _ = opts;
    return .{
        .renderer = renderer,
        .target = target,
    };
}

pub fn renderPass(
    self: *const Self,
    attachments: []const RenderPass.Options.Attachment,
) RenderPass {
    _ = self;
    return RenderPass.begin(.{ .attachments = attachments });
}

pub fn complete(self: *const Self, sync: bool) void {
    _ = sync;
    _ = self.target;
    self.renderer.frameCompleted(.healthy);
}
