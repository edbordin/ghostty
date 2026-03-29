//! Graphics API wrapper for D3D11 renderer scaffolding on Windows.
pub const D3D11 = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const zw = @import("zwindows");
const d3d = zw.d3d11;
const dxgi = zw.dxgi;

const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const rendererpkg = @import("../renderer.zig");
const shadertoy = @import("shadertoy.zig");
const Renderer = rendererpkg.GenericRenderer(D3D11);
const log = std.log.scoped(.d3d11);

const SurfaceSize = struct {
    width: u32,
    height: u32,
};

pub const GraphicsAPI = D3D11;
pub const Target = @import("d3d11/Target.zig");
pub const Frame = @import("d3d11/Frame.zig");
pub const RenderPass = @import("d3d11/RenderPass.zig");
pub const Pipeline = @import("d3d11/Pipeline.zig");
const bufferpkg = @import("d3d11/buffer.zig");
pub const Buffer = bufferpkg.Buffer;
pub const BufferHandle = bufferpkg.Handle;
pub const Sampler = @import("d3d11/Sampler.zig");
pub const Texture = @import("d3d11/Texture.zig");
pub const shaders = @import("d3d11/shaders.zig");
pub const api = @import("d3d11/api.zig");
const SwapChainPanel = @import("d3d11/SwapChainPanel.zig");
const win32ext = @import("d3d11/win32ext.zig");

pub const custom_shader_target: shadertoy.Target = .hlsl;
pub const custom_shader_y_is_down = false;

/// Number of in-flight generic frame slots; this is separate from DXGI
/// swapchain back-buffer count.
/// Because Direct3D manages its own swap chain, we don't need this to be >1.
pub const swap_chain_count = 1;

pub const BufferTarget = enum {
    array,
    uniform,
};

blending: configpkg.Config.AlphaBlending,
vsync: bool,
rt_surface: *apprt.Surface,
swap_chain_panel: ?*anyopaque = null,

// D3D11 device and context (moved from Runtime.State)
device: ?*d3d.IDevice = null,
context: ?*d3d.IDeviceContext = null,
// Swap chain (moved from Runtime.State)
swap_chain: ?*dxgi.ISwapChain1 = null,
swap_chain2: ?*dxgi.ISwapChain2 = null,
// Main render target view (moved from Runtime.State)
render_target: ?*d3d.IRenderTargetView = null,
// Composition scale for SwapChainPanel transform
composition_scale_x: f32 = 1.0,
composition_scale_y: f32 = 1.0,

last_target: ?Target = null,
size: SurfaceSize = .{ .width = 0, .height = 0 },
clear_color: [4]f32 = .{
    0.08,
    0.08,
    0.09,
    1.0,
},
present_calls: usize = 0,
present_last_calls: usize = 0,
pass_cleared: bool = false,
swapchain_pass_bound: bool = false,

pub fn init(alloc: Allocator, opts: rendererpkg.Options) !D3D11 {
    comptime switch (builtin.os.tag) {
        .windows => {},
        else => @compileError("unsupported platform for D3D11"),
    };

    var swap_chain_panel: ?*anyopaque = null;

    switch (apprt.runtime) {
        apprt.embedded => switch (opts.rt_surface.platform) {
            .windows => |v| {
                swap_chain_panel = v.swap_chain_panel;
            },
            else => {},
        },
        else => @compileError("unsupported apprt for D3D11"),
    }

    var size: SurfaceSize = .{ .width = 0, .height = 0 };
    if (opts.rt_surface.getSize()) |surface_size| {
        size = .{
            .width = surface_size.width,
            .height = surface_size.height,
        };
    } else |_| {
        size = .{
            .width = opts.size.screen.width,
            .height = opts.size.screen.height,
        };
    }

    var device: ?*d3d.IDevice = null;
    var context: ?*d3d.IDeviceContext = null;
    if (!createDevice(&device, &context)) {
        log.err("failed to create D3D11 device/context", .{});
        return error.D3D11Failed;
    }

    var swap_chain: ?*dxgi.ISwapChain1 = null;
    var swap_chain2: ?*dxgi.ISwapChain2 = null;
    var render_target: ?*d3d.IRenderTargetView = null;

    const panel = swap_chain_panel orelse {
        log.err("failed to initialize native D3D11 (swapchain_panel required)", .{});
        return error.D3D11Failed;
    };
    const safe_width = if (size.width > 0) size.width else 1;
    const safe_height = if (size.height > 0) size.height else 1;
    log.info("Creating swapchain with size={}x{} (from opts.rt_surface.getSize() or opts.size.screen)", .{ safe_width, safe_height });
    if (!createSwapChainForPanel(
        device.?,
        panel,
        safe_width,
        safe_height,
        &swap_chain,
        &swap_chain2,
        &render_target,
    )) {
        log.err("failed to create D3D11 swapchain/render target", .{});
        return error.D3D11Failed;
    }

    const initial_clear_color: [4]f32 = .{
        @as(f32, @floatFromInt(opts.config.background.r)) / 255.0,
        @as(f32, @floatFromInt(opts.config.background.g)) / 255.0,
        @as(f32, @floatFromInt(opts.config.background.b)) / 255.0,
        @floatCast(opts.config.background_opacity),
    };

    log.info(
        "initialized D3D11 scaffold swap_chain_panel={any} initial_clear={any}",
        .{ swap_chain_panel, initial_clear_color },
    );

    _ = alloc;
    return .{
        .blending = opts.config.blending,
        .vsync = opts.config.vsync,
        .rt_surface = opts.rt_surface,
        .swap_chain_panel = swap_chain_panel,
        .device = device,
        .context = context,
        .swap_chain = swap_chain,
        .swap_chain2 = swap_chain2,
        .render_target = render_target,
        .size = size,
        .clear_color = initial_clear_color,
    };
}

pub fn deinit(self: *D3D11) void {
    win32ext.releaseAndNull(d3d.IRenderTargetView, &self.render_target);
    win32ext.releaseAndNull(dxgi.ISwapChain2, &self.swap_chain2);
    win32ext.releaseAndNull(dxgi.ISwapChain1, &self.swap_chain);
    win32ext.releaseAndNull(d3d.IDeviceContext, &self.context);
    win32ext.releaseAndNull(d3d.IDevice, &self.device);
    self.* = undefined;
}

pub fn drawFrameStart(self: *D3D11) void {
    self.pass_cleared = false;
    self.swapchain_pass_bound = false;
}

pub fn drawFrameEnd(self: *D3D11) void {
    _ = self;
}

pub fn initShaders(
    self: *const D3D11,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    log.warn("initShaders custom_post_shader_count={}", .{custom_shaders.len});
    const device = self.device orelse return error.D3D11Failed;
    return try shaders.Shaders.init(alloc, device, custom_shaders);
}

pub fn surfaceSize(self: *const D3D11) !SurfaceSize {
    if (self.rt_surface.getSize()) |surface_size| {
        return .{
            .width = surface_size.width,
            .height = surface_size.height,
        };
    } else |_| {}

    return self.size;
}

pub fn initTarget(self: *const D3D11, width: usize, height: usize) !Target {
    _ = width;
    _ = height;
    const format = if (self.blending.isLinear())
        dxgi.FORMAT.B8G8R8A8_UNORM_SRGB
    else
        dxgi.FORMAT.B8G8R8A8_UNORM;
    const device = self.device orelse return error.D3D11Failed;
    const swapchain_rtv = self.render_target orelse return error.D3D11Failed;
    if (self.size.width == 0 or self.size.height == 0) return error.D3D11Failed;

    return Target.initSwapchain(
        device,
        swapchain_rtv,
        self.size.width,
        self.size.height,
        format,
    );
}

pub fn present(self: *D3D11, target: Target) error{PresentFailed}!void {
    return self.presentWithSync(target, true);
}

pub fn presentWithSync(
    self: *D3D11,
    target: Target,
    sync: bool,
) error{PresentFailed}!void {
    self.present_calls += 1;
    self.last_target = target;

    const swapchain_rtv = self.render_target orelse @panic("presentWithSync called without swapchain render target");
    const frame_rtv = target.render_target orelse @panic("presentWithSync called without frame render target");
    if (frame_rtv != swapchain_rtv) {
        @panic("presentWithSync expects a swapchain-backed frame target");
    }
    if (builtin.mode == .Debug) {
        std.debug.assert(target.texture == null);
    }

    const sync_interval = presentSyncInterval(self, sync);
    self.updateCompositionScale();
    const presented = self.presentOnly(sync_interval);

    if (self.present_calls <= 8 or !presented) {
        log.info(
            "present call={} size={}x{} scale={d:.3}x{d:.3} presented={} interval={} config_vsync={} pass_cleared={} text_drawn={} clear={any}",
            .{
                self.present_calls,
                self.size.width,
                self.size.height,
                self.composition_scale_x,
                self.composition_scale_y,
                presented,
                sync_interval,
                self.vsync,
                self.swapchain_pass_bound,
                false,
                self.clear_color,
            },
        );
    }
    if (!presented) return error.PresentFailed;
}

pub fn presentLastTarget(self: *D3D11) error{PresentFailed}!void {
    self.present_last_calls += 1;
    _ = self.last_target;

    _ = self.device orelse @panic("presentLastTarget called without device");
    _ = self.swap_chain orelse @panic("presentLastTarget called without swapchain");
    if (self.size.width == 0 or self.size.height == 0) return;

    self.updateCompositionScale();
    const sync_interval = presentSyncInterval(self, false);
    const presented = self.presentOnlyWithFlags(
        sync_interval,
        .{ .DO_NOT_SEQUENCE = true },
    );
    if (self.present_last_calls <= 8 or !presented) {
        log.info(
            "presentLastTarget call={} size={}x{} scale={d:.3}x{d:.3} presented={} interval={} config_vsync={} clear={any}",
            .{
                self.present_last_calls,
                self.size.width,
                self.size.height,
                self.composition_scale_x,
                self.composition_scale_y,
                presented,
                sync_interval,
                self.vsync,
                self.clear_color,
            },
        );
    }
    if (!presented) return error.PresentFailed;
}

fn presentSyncInterval(self: *const D3D11, sync: bool) u32 {
    // `sync` is an explicit request to block until the next vblank.
    // Otherwise, use the renderer's `window-vsync` setting.
    return if (sync or self.vsync) 1 else 0;
}

pub fn setPassClearColor(self: *D3D11, color: [4]f32) void {
    self.clear_color = color;
}

pub fn setPassClearColorFromU8(self: *D3D11, color: [4]u8) void {
    self.clear_color = .{
        @as(f32, @floatFromInt(color[0])) / 255.0,
        @as(f32, @floatFromInt(color[1])) / 255.0,
        @as(f32, @floatFromInt(color[2])) / 255.0,
        @as(f32, @floatFromInt(color[3])) / 255.0,
    };
}

pub fn updateCompositionScale(self: *D3D11) void {
    const scale = self.rt_surface.getContentScale() catch .{ .x = 1.0, .y = 1.0 };
    const safe_x = sanitizeScale(@floatCast(scale.x));
    const safe_y = sanitizeScale(@floatCast(scale.y));

    if (self.composition_scale_x != safe_x or self.composition_scale_y != safe_y) {
        log.info("composition scale changed {}x{} -> {}x{}", .{ self.composition_scale_x, self.composition_scale_y, safe_x, safe_y });
        self.composition_scale_x = safe_x;
        self.composition_scale_y = safe_y;
        _ = self.applyCompositionScaleTransform();
    }
}

pub fn beginFrame(
    self: *D3D11,
    renderer: *Renderer,
    target: *Target,
) !Frame {
    self.last_target = target.*;
    self.updateCompositionScale();

    // Check for size changes at the start of the frame and resize immediately.
    // This prevents the latency of deferring resize until present(), which
    // causes the "pause before new size takes effect" during window resize.
    if (self.rt_surface.getSize()) |surface_size| {
        const needs_resize = surface_size.width != self.size.width or
            surface_size.height != self.size.height or
            self.render_target == null;
        if (needs_resize and surface_size.width > 0 and surface_size.height > 0) {
            log.info("beginFrame: immediate resize to {}x{}", .{ surface_size.width, surface_size.height });
            if (!self.resize(surface_size.width, surface_size.height)) {
                return error.D3D11Failed;
            }
        }
    } else |_| {}

    self.refreshFrameTarget(target);

    return try Frame.begin(.{}, renderer, target);
}

fn refreshFrameTarget(self: *D3D11, target: *Target) void {
    const device = self.device orelse return;
    const swapchain_rtv = self.render_target orelse return;
    if (self.size.width == 0 or self.size.height == 0) return;

    const format = if (self.blending.isLinear())
        dxgi.FORMAT.B8G8R8A8_UNORM_SRGB
    else
        dxgi.FORMAT.B8G8R8A8_UNORM;

    // If the frame target currently owns an offscreen resource, release it and
    // replace it with a non-owning handle to the current swapchain backbuffer.
    if (target.owns_resources) {
        target.deinit();
        target.* = Target.initSwapchain(
            device,
            swapchain_rtv,
            self.size.width,
            self.size.height,
            format,
        );
        return;
    }

    // Keep existing non-owning target in sync with swapchain RTV recreations.
    target.render_target = swapchain_rtv;
    target.width = self.size.width;
    target.height = self.size.height;
    target.format = format;
    target.texture = null;
    target.shader_view = null;
}

pub const PassAttachment = struct {
    target: union(enum) {
        texture: Texture,
        target: Target,
    },
    clear_color: ?[4]f32 = null,
};

pub const PreparedPass = struct {
    context: *d3d.IDeviceContext,
    render_target: *d3d.IRenderTargetView,
    width: u32,
    height: u32,
};

pub fn setupPass(self: *D3D11, attachments: []const PassAttachment) PreparedPass {
    if (attachments.len == 0) {
        @panic("setupPass requires at least one attachment");
    }
    const context = self.context orelse @panic("setupPass called without device context");
    if (self.size.width == 0 or self.size.height == 0) {
        @panic("setupPass called with zero-sized surface");
    }

    // Extract clear color from the first attachment
    var attachment_clear: ?[4]f32 = null;
    if (attachments[0].clear_color) |clear| {
        attachment_clear = clear;
    }

    const attachment_type = @tagName(attachments[0].target);
    log.debug("setupPass attachment type={s}", .{attachment_type});

    var pass_target: PassTarget = .{};
    var resolved_rtv: ?*d3d.IRenderTargetView = null;
    var resolved_width: u32 = 0;
    var resolved_height: u32 = 0;

    switch (attachments[0].target) {
        .target => |t| {
            if (t.width == 0 or t.height == 0) {
                @panic("setupPass target attachment has zero size");
            }
            const pass_rtv = t.render_target orelse @panic("setupPass target attachment missing render target view");

            resolved_rtv = pass_rtv;
            resolved_width = @intCast(t.width);
            resolved_height = @intCast(t.height);

            if (self.render_target) |swapchain_rtv| {
                if (pass_rtv == swapchain_rtv) {
                    pass_target = .{ .kind = .swapchain };
                } else {
                    pass_target = .{
                        .kind = .texture,
                        .render_target = pass_rtv,
                        .width = @intCast(t.width),
                        .height = @intCast(t.height),
                    };
                }
            } else {
                pass_target = .{
                    .kind = .texture,
                    .render_target = pass_rtv,
                    .width = @intCast(t.width),
                    .height = @intCast(t.height),
                };
            }
        },
        .texture => |texture| {
            if (texture.width == 0 or texture.height == 0) {
                @panic("setupPass texture attachment has zero size");
            }
            if (builtin.mode == .Debug) {
                std.debug.assert(texture.render_target != null);
            }
            const pass_rtv = texture.render_target orelse @panic("setupPass texture attachment missing render target view");
            resolved_rtv = pass_rtv;
            resolved_width = @intCast(texture.width);
            resolved_height = @intCast(texture.height);
            pass_target = .{
                .kind = .texture,
                .render_target = pass_rtv,
                .width = @intCast(texture.width),
                .height = @intCast(texture.height),
            };
        },
    }

    if (resolved_rtv == null or resolved_width == 0 or resolved_height == 0) {
        @panic("setupPass failed to resolve attachment render target");
    }
    if (!self.beginPass(pass_target, attachment_clear)) {
        @panic("setupPass failed to begin pass");
    }

    switch (pass_target.kind) {
        .swapchain => log.debug("setupPass swapchain pass bound ok", .{}),
        .texture => log.debug("setupPass texture pass bound ok", .{}),
    }

    return .{
        .context = context,
        .render_target = resolved_rtv.?,
        .width = resolved_width,
        .height = resolved_height,
    };
}

pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;
}

pub fn finalizeSurfaceInit(self: *const D3D11, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

pub fn threadEnter(self: *const D3D11, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

pub fn threadExit(self: *const D3D11) void {
    _ = self;
}

pub fn loopEnter(self: *const D3D11) void {
    _ = self;
}

pub fn loopExit(self: *const D3D11) void {
    _ = self;
}

pub fn displayRealized(self: *D3D11) void {
    _ = self;
}

pub fn displayUnrealized(self: *D3D11) void {
    _ = self;
}

pub inline fn bufferOptions(self: D3D11) bufferpkg.Options {
    return .{
        .device = self.device orelse unreachable,
        .context = self.context orelse unreachable,
        .target = .array,
    };
}

pub const instanceBufferOptions = bufferOptions;
pub const fgBufferOptions = bufferOptions;
pub const imageBufferOptions = bufferOptions;
pub const bgImageBufferOptions = bufferOptions;

pub inline fn uniformBufferOptions(self: D3D11) bufferpkg.Options {
    var opts = self.bufferOptions();
    opts.target = .uniform;
    return opts;
}

pub inline fn bgBufferOptions(self: D3D11) bufferpkg.Options {
    var opts = self.bufferOptions();
    opts.shader_resource_format = dxgi.FORMAT.R8G8B8A8_UNORM;
    return opts;
}

pub inline fn textureOptions(self: D3D11) Texture.Options {
    return .{
        .device = self.device orelse unreachable,
        .context = self.context orelse unreachable,
        .format = dxgi.FORMAT.B8G8R8A8_UNORM_SRGB,
        .render_target = true,
    };
}

pub inline fn samplerOptions(self: D3D11) Sampler.Options {
    return .{
        .device = self.device orelse unreachable,
        .filter = d3d.FILTER.MIN_MAG_MIP_LINEAR,
        .address_u = d3d.TEXTURE_ADDRESS_MODE.CLAMP,
        .address_v = d3d.TEXTURE_ADDRESS_MODE.CLAMP,
    };
}

pub const ImageTextureFormat = enum {
    gray,
    rgba,
    bgra,

    fn toDxgiFormat(self: ImageTextureFormat, srgb: bool) dxgi.FORMAT {
        return switch (self) {
            .gray => if (srgb) dxgi.FORMAT.R8_UNORM else dxgi.FORMAT.R8_UNORM, // R8 has no sRGB variant
            .rgba => if (srgb) dxgi.FORMAT.R8G8B8A8_UNORM_SRGB else dxgi.FORMAT.R8G8B8A8_UNORM,
            .bgra => if (srgb) dxgi.FORMAT.B8G8R8A8_UNORM_SRGB else dxgi.FORMAT.B8G8R8A8_UNORM,
        };
    }
};

pub inline fn imageTextureOptions(
    self: D3D11,
    format: ImageTextureFormat,
    srgb: bool,
) Texture.Options {
    return .{
        .device = self.device orelse unreachable,
        .context = self.context orelse unreachable,
        .format = format.toDxgiFormat(srgb),
        .render_target = false,
    };
}

pub fn initAtlasTexture(
    self: *const D3D11,
    atlas: *const font.Atlas,
) (Texture.Error || error{UnsupportedAtlasFormat})!Texture {
    const format = switch (atlas.format) {
        .grayscale => dxgi.FORMAT.R8_UNORM,
        .bgr => return error.UnsupportedAtlasFormat,
        .bgra => dxgi.FORMAT.B8G8R8A8_UNORM_SRGB,
    };
    return Texture.init(
        .{
            .device = self.device orelse unreachable,
            .context = self.context orelse unreachable,
            .format = format,
            .render_target = false,
        },
        atlas.size,
        atlas.size,
        null,
    );
}

fn createDevice(
    out_device: *?*d3d.IDevice,
    out_context: *?*d3d.IDeviceContext,
) bool {
    const d3dcommon = zw.d3d;
    const levels = [_]d3dcommon.FEATURE_LEVEL{
        d3dcommon.FEATURE_LEVEL.@"11_1",
        d3dcommon.FEATURE_LEVEL.@"11_0",
        d3dcommon.FEATURE_LEVEL.@"10_1",
        d3dcommon.FEATURE_LEVEL.@"10_0",
    };

    const fallback_levels = [_]d3dcommon.FEATURE_LEVEL{
        d3dcommon.FEATURE_LEVEL.@"11_0",
        d3dcommon.FEATURE_LEVEL.@"10_1",
        d3dcommon.FEATURE_LEVEL.@"10_0",
    };

    const d3d_ext = zw.d3d11_ext;
    var flags: d3d.CREATE_DEVICE_FLAG = .{ .BGRA_SUPPORT = true };
    if (builtin.mode == .Debug) flags.DEBUG = true;

    var device: ?*d3d.IDevice = null;
    var context: ?*d3d.IDeviceContext = null;
    var created_level: d3dcommon.FEATURE_LEVEL = d3dcommon.FEATURE_LEVEL.@"11_0";

    var hr = d3d_ext.D3D11CreateDevice(
        null,
        d3dcommon.DRIVER_TYPE.HARDWARE,
        null,
        flags,
        levels[0..].ptr,
        levels.len,
        d3d.SDK_VERSION,
        @ptrCast(&device),
        &created_level,
        @ptrCast(&context),
    );

    if (hr == zw.E_INVALIDARG) {
        hr = d3d_ext.D3D11CreateDevice(
            null,
            d3dcommon.DRIVER_TYPE.HARDWARE,
            null,
            flags,
            fallback_levels[0..].ptr,
            fallback_levels.len,
            d3d.SDK_VERSION,
            @ptrCast(&device),
            &created_level,
            @ptrCast(&context),
        );
    }

    if (hr < 0 and flags.DEBUG) {
        flags.DEBUG = false;
        hr = d3d_ext.D3D11CreateDevice(
            null,
            d3dcommon.DRIVER_TYPE.HARDWARE,
            null,
            flags,
            levels[0..].ptr,
            levels.len,
            d3d.SDK_VERSION,
            @ptrCast(&device),
            &created_level,
            @ptrCast(&context),
        );

        if (hr == zw.E_INVALIDARG) {
            hr = d3d_ext.D3D11CreateDevice(
                null,
                d3dcommon.DRIVER_TYPE.HARDWARE,
                null,
                flags,
                fallback_levels[0..].ptr,
                fallback_levels.len,
                d3d.SDK_VERSION,
                @ptrCast(&device),
                &created_level,
                @ptrCast(&context),
            );
        }
    }

    if (hr < 0) {
        hr = d3d_ext.D3D11CreateDevice(
            null,
            d3dcommon.DRIVER_TYPE.WARP,
            null,
            flags,
            levels[0..].ptr,
            levels.len,
            d3d.SDK_VERSION,
            @ptrCast(&device),
            &created_level,
            @ptrCast(&context),
        );

        if (hr == zw.E_INVALIDARG) {
            hr = d3d_ext.D3D11CreateDevice(
                null,
                d3dcommon.DRIVER_TYPE.WARP,
                null,
                flags,
                fallback_levels[0..].ptr,
                fallback_levels.len,
                d3d.SDK_VERSION,
                @ptrCast(&device),
                &created_level,
                @ptrCast(&context),
            );
        }
    }

    if (hr < 0 or device == null or context == null) return false;
    out_device.* = device;
    out_context.* = context;
    return true;
}

fn createSwapChainForPanel(
    device: *d3d.IDevice,
    swap_chain_panel: ?*anyopaque,
    width: u32,
    height: u32,
    out_swap_chain: *?*dxgi.ISwapChain1,
    out_swap_chain2: *?*dxgi.ISwapChain2,
    out_render_target: *?*d3d.IRenderTargetView,
) bool {
    if (swap_chain_panel == null) return false;

    var dxgi_device: ?*dxgi.IDevice = null;
    const dxgi_device_hr = device.QueryInterface(
        &dxgi.IID_IDevice,
        @ptrCast(&dxgi_device),
    );
    if (dxgi_device_hr < 0 or dxgi_device == null) return false;
    defer _ = dxgi_device.?.Release();

    var adapter: ?*dxgi.IAdapter = null;
    const adapter_hr = dxgi_device.?.GetAdapter(&adapter);
    if (adapter_hr < 0 or adapter == null) return false;
    defer _ = adapter.?.Release();

    var factory_opaque: ?*anyopaque = null;
    const factory_hr = adapter.?.GetParent(
        &zw.GUID.parse("{50c83a1c-e072-4c48-87b0-3630fa36a6d0}"),
        &factory_opaque,
    );
    if (factory_hr < 0 or factory_opaque == null) return false;

    const factory: *dxgi.IFactory2 = @ptrCast(@alignCast(factory_opaque.?));
    defer _ = factory.Release();

    const desc: dxgi.SWAP_CHAIN_DESC1 = .{
        .Width = width,
        .Height = height,
        .Format = dxgi.FORMAT.B8G8R8A8_UNORM,
        .Stereo = zw.FALSE,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BufferUsage = dxgi.USAGE{ .RENDER_TARGET_OUTPUT = true },
        .BufferCount = 2,
        .Scaling = dxgi.SCALING.STRETCH,
        .SwapEffect = dxgi.SWAP_EFFECT.FLIP_SEQUENTIAL,
        .AlphaMode = dxgi.ALPHA_MODE.PREMULTIPLIED,
        .Flags = .{},
    };

    const dxgi_ext = zw.dxgi_ext;
    var swap_chain: ?*dxgi.ISwapChain1 = null;
    const create_hr = dxgi_ext.CreateSwapChainForComposition(
        factory,
        @ptrCast(device),
        &desc,
        null,
        &swap_chain,
    );
    if (create_hr < 0 or swap_chain == null) return false;

    var swap_chain2: ?*dxgi.ISwapChain2 = null;
    const swap_chain2_hr = swap_chain.?.QueryInterface(
        &dxgi.IID_ISwapChain2,
        @ptrCast(&swap_chain2),
    );
    if (swap_chain2_hr < 0 or swap_chain2 == null) {
        _ = swap_chain.?.Release();
        return false;
    }

    const panel = SwapChainPanel.init(swap_chain_panel.?);
    if (!panel.setSwapChain(swap_chain.?)) {
        _ = swap_chain2.?.Release();
        _ = swap_chain.?.Release();
        return false;
    }

    // Create the render target view
    var back_buffer: *d3d.ITexture2D = undefined;
    const hr = swap_chain.?.GetBuffer(
        0,
        &d3d.IID_ITexture2D,
        @ptrCast(&back_buffer),
    );
    if (hr < 0) {
        _ = swap_chain2.?.Release();
        _ = swap_chain.?.Release();
        return false;
    }
    defer _ = back_buffer.Release();

    var rtv: ?*d3d.IRenderTargetView = null;
    const rtv_hr = device.CreateRenderTargetView(
        @ptrCast(back_buffer),
        null,
        @ptrCast(&rtv),
    );
    if (rtv_hr < 0 or rtv == null) {
        _ = swap_chain2.?.Release();
        _ = swap_chain.?.Release();
        return false;
    }

    out_swap_chain.* = swap_chain;
    out_swap_chain2.* = swap_chain2;
    out_render_target.* = rtv;
    return true;
}

fn createRenderTarget(self: *D3D11) bool {
    if (self.device == null or self.swap_chain == null) return false;

    var back_buffer: *d3d.ITexture2D = undefined;
    const hr = self.swap_chain.?.GetBuffer(
        0,
        &d3d.IID_ITexture2D,
        @ptrCast(&back_buffer),
    );
    if (hr < 0) return false;
    defer _ = back_buffer.Release();

    var rtv: ?*d3d.IRenderTargetView = null;
    const rtv_hr = self.device.?.CreateRenderTargetView(
        @ptrCast(back_buffer),
        null,
        @ptrCast(&rtv),
    );
    if (rtv_hr < 0 or rtv == null) return false;
    self.render_target = rtv;
    return true;
}

fn applyCompositionScaleTransform(self: *D3D11) bool {
    if (self.swap_chain2 == null) return false;

    // SwapChainPanel/WinUI applies composition scaling; apply the inverse
    // so Ghostty renders at full native resolution:
    // https://stackoverflow.com/a/42543636
    const matrix: dxgi.MATRIX_3X2_F = .{
        ._11 = 1.0 / self.composition_scale_x,
        ._12 = 0.0,
        ._21 = 0.0,
        ._22 = 1.0 / self.composition_scale_y,
        ._31 = 0.0,
        ._32 = 0.0,
    };
    const hr = self.swap_chain2.?.SetMatrixTransform(&matrix);
    return hr >= 0;
}

fn sanitizeScale(scale: f32) f32 {
    if (!std.math.isFinite(scale) or scale <= 0.0) return 1.0;
    return scale;
}

pub fn resize(self: *D3D11, width: u32, height: u32) bool {
    log.info("D3D11.resize requested {}x{} current size={}x{}", .{ width, height, self.size.width, self.size.height });
    if (self.swap_chain == null or self.context == null or width == 0 or height == 0) {
        log.warn("D3D11.resize early return swapchain={} context={}", .{ self.swap_chain != null, self.context != null });
        return false;
    }

    if (self.size.width == width and self.size.height == height and self.render_target != null) {
        log.info("D3D11.resize already correct size {}x{}", .{ width, height });
        return true;
    }

    var null_target: ?*d3d.IRenderTargetView = null;
    self.context.?.OMSetRenderTargets(
        1,
        @ptrCast(&null_target),
        null,
    );

    win32ext.releaseAndNull(d3d.IRenderTargetView, &self.render_target);

    log.info("ResizeBuffers from current size to {}x{}", .{ width, height });
    const hr = self.swap_chain.?.ResizeBuffers(
        0,
        width,
        height,
        dxgi.FORMAT.UNKNOWN,
        .{},
    );
    if (hr < 0) {
        log.warn("ResizeBuffers failed hr={}", .{hr});
        return false;
    }

    _ = self.applyCompositionScaleTransform();
    if (!self.createRenderTarget()) return false;

    self.size.width = width;
    self.size.height = height;
    log.info("D3D11.resize success {}x{}", .{ width, height });
    return true;
}

pub fn presentOnly(self: *D3D11, sync_interval: u32) bool {
    return self.presentOnlyWithFlags(sync_interval, .{});
}

fn presentOnlyWithFlags(
    self: *D3D11,
    sync_interval: u32,
    flags: dxgi.PRESENT_FLAG,
) bool {
    if (self.swap_chain == null) return false;
    const hr = self.swap_chain.?.Present(sync_interval, flags);
    return hr >= 0 or hr == dxgi.STATUS_OCCLUDED;
}

pub fn presentClear(self: *D3D11, clear_color: [4]f32, sync_interval: u32) bool {
    if (!self.beginPass(.{ .kind = .swapchain }, clear_color)) return false;
    return self.presentOnly(sync_interval);
}

pub const PassTarget = struct {
    kind: enum {
        swapchain,
        texture,
    } = .swapchain,
    render_target: ?*d3d.IRenderTargetView = null,
    width: u32 = 0,
    height: u32 = 0,
};

pub fn beginPass(self: *D3D11, target: PassTarget, clear_color: ?[4]f32) bool {
    if (self.context == null) return false;

    var render_target: ?*d3d.IRenderTargetView = null;
    var width: u32 = 0;
    var height: u32 = 0;

    switch (target.kind) {
        .swapchain => {
            render_target = self.render_target;
            width = self.size.width;
            height = self.size.height;
            self.swapchain_pass_bound = true;
        },
        .texture => {
            if (target.render_target == null) return false;
            if (target.width == 0 or target.height == 0) return false;
            render_target = target.render_target;
            width = target.width;
            height = target.height;
            self.swapchain_pass_bound = false;
        },
    }

    if (render_target == null or width == 0 or height == 0) return false;

    var bound = render_target;
    self.context.?.OMSetRenderTargets(1, @ptrCast(&bound), null);
    var viewport = d3d.VIEWPORT{
        .TopLeftX = 0,
        .TopLeftY = 0,
        .Width = @floatFromInt(width),
        .Height = @floatFromInt(height),
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    };
    self.context.?.RSSetViewports(1, @ptrCast(&viewport));

    if (clear_color) |clear| {
        self.context.?.ClearRenderTargetView(render_target.?, @ptrCast(&clear));
    }
    return true;
}
