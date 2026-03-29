//! Wrapper for D3D11 render passes.
const Self = @This();

const std = @import("std");
const Pipeline = @import("Pipeline.zig");
const Sampler = @import("Sampler.zig");
const Texture = @import("Texture.zig");
const Target = @import("Target.zig");
const Buffer = @import("buffer.zig");
const shaderspkg = @import("shaders.zig");
const d3dapi = @import("api.zig");
const zw = @import("zwindows");
const d3d = zw.d3d11;
const d3d_ext = zw.d3d11_ext;
const log = std.log.scoped(.d3d11_renderpass);

// Keep a small guard range for SRV unbind when transitioning between passes.
// Current D3D11 pipelines bind SRVs in slots 0..2.
const alias_guard_srv_slots: u32 = 4;

pub const Options = struct {
    attachments: []const Attachment,
    /// D3D11 device context for drawing commands
    context: *d3d.IDeviceContext,
    /// Current render target view
    render_target: *d3d.IRenderTargetView,
    /// Current surface size
    width: u32,
    height: u32,

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
    uniforms: ?Buffer.Handle = null,
    buffers: []const ?Buffer.Handle = &.{},
    textures: []const ?Texture = &.{},
    samplers: []const ?Sampler = &.{},
    draw: Draw,

    pub const Draw = struct {
        type: d3dapi.Primitive,
        vertex_count: usize,
        instance_count: usize = 1,
    };
};

attachments: []const Options.Attachment,
context: *d3d.IDeviceContext,
render_target: *d3d.IRenderTargetView,
width: u32,
height: u32,
step_number: usize = 0,
constants_buffer: ?*d3d.IBuffer = null,
srvs_cleared_for_pass: bool = false,

pub fn begin(opts: Options) Self {
    log.debug("RenderPass.begin attachments_len={}", .{opts.attachments.len});
    return .{
        .attachments = opts.attachments,
        .context = opts.context,
        .render_target = opts.render_target,
        .width = opts.width,
        .height = opts.height,
    };
}

pub fn step(self: *Self, s: Step) void {
    switch (s.pipeline.kind) {
        .bg_color, .bg_image, .cell_bg, .cell_text, .image, .postprocess => _ = self.drawGenericStep(s),
        else => {},
    }

    self.step_number += 1;
}

pub fn complete(self: *const Self) void {
    _ = self;
    // Unlike Metal (which closes a command encoder) or OpenGL (which flushes),
    // D3D11's immediate context model doesn't require work here. All state
    // binding and draw calls happen during step(), and present() (called in
    // Frame.complete()) is what triggers GPU execution. The driver manages
    // the command queue implicitly.
}

fn drawGenericStep(self: *Self, s: Step) bool {
    if (s.draw.instance_count == 0) return true;

    const context = self.context;
    if (self.width == 0 or self.height == 0) {
        log.warn("skip draw: zero bound size kind={s} size={}x{}", .{
            @tagName(s.pipeline.kind),
            self.width,
            self.height,
        });
        return false;
    }

    const native = s.pipeline.native;
    const vs = native.vertex_shader orelse {
        log.warn("skip draw: missing vertex shader kind={s}", .{@tagName(s.pipeline.kind)});
        return false;
    };
    const ps = native.pixel_shader orelse {
        log.warn("skip draw: missing pixel shader kind={s}", .{@tagName(s.pipeline.kind)});
        return false;
    };

    if (!self.srvs_cleared_for_pass) {
        // D3D11 state is sticky across passes. Clear a narrow SRV range once
        // at pass start to avoid SRV/RTV aliasing hazards on ping-pong targets.
        clearBoundSrvs(context);
        self.srvs_cleared_for_pass = true;
    }

    context.IASetInputLayout(native.input_layout);
    context.IASetPrimitiveTopology(s.draw.type.toD3D());

    if (s.pipeline.stride > 0) {
        if (s.buffers.len == 0) {
            log.warn("skip draw: missing vertex buffer binding kind={s}", .{@tagName(s.pipeline.kind)});
            return false;
        }
        const buf = s.buffers[0] orelse {
            log.warn("skip draw: null vertex buffer handle kind={s}", .{@tagName(s.pipeline.kind)});
            return false;
        };
        const vb_native = buf.native orelse {
            log.warn("skip draw: vertex buffer has no native resource kind={s}", .{@tagName(s.pipeline.kind)});
            return false;
        };
        if (buf.stride == 0) {
            log.warn("skip draw: zero vertex stride kind={s}", .{@tagName(s.pipeline.kind)});
            return false;
        }
        var vb: ?*d3d.IBuffer = vb_native;
        const strides = [_]u32{@intCast(buf.stride)};
        const offsets = [_]u32{0};
        context.IASetVertexBuffers(
            0,
            1,
            @ptrCast(&vb),
            strides[0..].ptr,
            offsets[0..].ptr,
        );
    } else {
        var null_vb: ?*d3d.IBuffer = null;
        const zero = [_]u32{0};
        context.IASetVertexBuffers(0, 1, @ptrCast(&null_vb), zero[0..].ptr, zero[0..].ptr);
    }

    context.VSSetShader(vs, null, 0);
    context.PSSetShader(ps, null, 0);

    if (!bindConstants(self, s, context)) {
        log.warn("skip draw: constants not bound kind={s}", .{@tagName(s.pipeline.kind)});
        return false;
    }
    if (!bindTextures(self, s, context)) return false;
    bindSamplers(self, s, context);

    const blend_factor = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    context.OMSetBlendState(native.blend_state, &blend_factor, 0xFFFF_FFFF);

    if (s.pipeline.step_fn == .per_instance or s.draw.instance_count > 1) {
        d3d_ext.DrawInstanced(
            context,
            @intCast(s.draw.vertex_count),
            @intCast(s.draw.instance_count),
            0,
            0,
        );
    } else {
        context.Draw(@intCast(s.draw.vertex_count), 0);
    }

    return true;
}

fn bindConstants(self: *Self, s: Step, context: *d3d.IDeviceContext) bool {
    const layout = s.pipeline.layout.constant_buffer_slots;
    if (layout.vertex == null and layout.pixel == null) return true;

    if (s.uniforms) |uniforms| {
        const byte_size = uniforms.len * uniforms.stride;
        if (byte_size < @sizeOf(shaderspkg.Uniforms)) {
            log.warn("uniform buffer too small kind={s} bytes={} required={}", .{
                @tagName(s.pipeline.kind),
                byte_size,
                @sizeOf(shaderspkg.Uniforms),
            });
            return false;
        }
        const native_cb = uniforms.native orelse {
            log.warn("uniform buffer missing native resource kind={s}", .{@tagName(s.pipeline.kind)});
            return false;
        };
        self.constants_buffer = native_cb;
    } else if (self.constants_buffer == null) {
        // Some steps (for example image passes) rely on constants set by
        // an earlier step in the same render pass.
        log.warn("no constants available kind={s}", .{@tagName(s.pipeline.kind)});
        return false;
    }

    const cb = self.constants_buffer orelse return false;

    if (layout.vertex) |slot| {
        var vcb = cb;
        context.VSSetConstantBuffers(slot, 1, @ptrCast(&vcb));
    }
    if (layout.pixel) |slot| {
        var pcb = cb;
        context.PSSetConstantBuffers(slot, 1, @ptrCast(&pcb));
    }

    return true;
}

fn bindTextures(self: *Self, s: Step, context: *d3d.IDeviceContext) bool {
    _ = self;
    for (s.pipeline.layout.srv_slots, 0..) |slot, i| {
        var view: ?*d3d.IShaderResourceView = null;
        if (i < s.textures.len) {
            if (s.textures[i]) |tex| {
                view = tex.shader_view;
            }
        }
        if (view == null and slot >= 2) {
            const buf_index: usize = @intCast(slot - 1);
            if (buf_index < s.buffers.len) {
                if (s.buffers[buf_index]) |buf| {
                    view = buf.shader_view;
                }
            }
        }
        context.PSSetShaderResources(slot, 1, @ptrCast(&view));
    }
    return true;
}

fn bindSamplers(_: *Self, s: Step, context: *d3d.IDeviceContext) void {
    for (s.pipeline.layout.sampler_slots, 0..) |slot, i| {
        var sampler: ?*d3d.ISamplerState = null;
        if (i < s.samplers.len) {
            if (s.samplers[i]) |step_sampler| sampler = step_sampler.state;
        }
        if (sampler == null) sampler = s.pipeline.native.default_sampler;
        context.PSSetSamplers(slot, 1, @ptrCast(&sampler));
    }
}

fn clearBoundSrvs(context: *d3d.IDeviceContext) void {
    var null_views = [_]?*d3d.IShaderResourceView{null} ** alias_guard_srv_slots;
    context.PSSetShaderResources(0, alias_guard_srv_slots, @ptrCast(null_views[0..].ptr));
}
