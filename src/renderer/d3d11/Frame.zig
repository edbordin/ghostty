//! Wrapper for noop frame handling.
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
    return RenderPass.begin(.{
        .renderer = self.renderer,
        .attachments = attachments,
    });
}

pub fn complete(self: *const Self, sync: bool) void {
    _ = sync;
    const health: Health = .healthy;
    self.renderer.api.present(self.target.*) catch |err| {
        log.err("Failed to present render target: err={}", .{err});
        self.renderer.frameCompleted(.unhealthy);
        return;
    };
    self.renderer.frameCompleted(health);
}
