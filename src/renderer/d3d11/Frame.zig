//! Wrapper for D3D11 frame handling.
const Self = @This();

const std = @import("std");
const Renderer = @import("../generic.zig").Renderer(D3D11);
const D3D11 = @import("../D3D11.zig");
const Target = @import("Target.zig");
const RenderPass = @import("RenderPass.zig");
const Health = @import("../../renderer.zig").Health;
const log = std.log.scoped(.d3d11);

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
    if (attachments.len == 0) {
        @panic("renderPass requires at least one attachment");
    }

    // Set up the render pass before creating the RenderPass wrapper.
    // This resolves and binds the render target for the pass.
    const first_attachment = attachments[0];
    const converted_attachment = [_]D3D11.PassAttachment{.{
        .target = switch (first_attachment.target) {
            .texture => |tex| .{ .texture = tex },
            .target => |tgt| .{ .target = tgt },
        },
        .clear_color = first_attachment.clear_color,
    }};
    const prepared = self.renderer.api.setupPass(&converted_attachment);

    return RenderPass.begin(.{
        .attachments = attachments,
        .context = prepared.context,
        .render_target = prepared.render_target,
        .width = prepared.width,
        .height = prepared.height,
    });
}

pub fn complete(self: *const Self, sync: bool) void {
    const health: Health = .healthy;
    self.renderer.api.presentWithSync(self.target.*, sync) catch |err| {
        log.err("Failed to present render target: err={}", .{err});
        self.renderer.frameCompleted(.unhealthy);
        return;
    };
    self.renderer.frameCompleted(health);
}
