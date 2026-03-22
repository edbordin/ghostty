//! Graphics API wrapper for D3D11 renderer scaffolding on Windows.
pub const D3D11 = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const rendererpkg = @import("../renderer.zig");
const shadertoy = @import("shadertoy.zig");
const Renderer = rendererpkg.GenericRenderer(D3D11);
const log = std.log.scoped(.d3d11);
const interoppkg = @import("d3d11/interop.zig");

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

pub const custom_shader_target: shadertoy.Target = .glsl;
pub const custom_shader_y_is_down = false;

/// Single buffering is enough for scaffolding.
pub const swap_chain_count = 1;

pub const BufferTarget = enum {
    array,
};

pub const BufferUsage = enum {
    dynamic_draw,
};

alloc: Allocator,
blending: configpkg.Config.AlphaBlending,
rt_surface: *apprt.Surface,
swap_chain_panel: ?*anyopaque = null,
interop: interoppkg.State = .{},
interop_ready: bool = false,
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

pub fn init(alloc: Allocator, opts: rendererpkg.Options) error{}!D3D11 {
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

    var interop: interoppkg.State = .{};
    const interop_ready = interop.init(
        swap_chain_panel,
        size.width,
        size.height,
    );
    if (!interop_ready) {
        log.warn("failed to initialize native D3D11 interop (swap_chain_panel required)", .{});
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

    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
        .rt_surface = opts.rt_surface,
        .swap_chain_panel = swap_chain_panel,
        .interop = interop,
        .interop_ready = interop_ready,
        .size = size,
        .clear_color = initial_clear_color,
    };
}

pub fn deinit(self: *D3D11) void {
    if (self.interop_ready) {
        self.interop.deinit();
    }
    self.* = undefined;
}

pub fn drawFrameStart(self: *D3D11) void {
    _ = self;
}

pub fn drawFrameEnd(self: *D3D11) void {
    _ = self;
}

pub fn initShaders(
    self: *const D3D11,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    _ = self;
    return try shaders.Shaders.init(alloc, custom_shaders);
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
    return Target.init(.{
        .width = width,
        .height = height,
        .internal_format = if (self.blending.isLinear()) .srgba else .rgba,
    });
}

pub fn present(self: *D3D11, target: Target) !void {
    self.present_calls += 1;
    self.last_target = target;
    self.size = .{
        .width = @intCast(target.width),
        .height = @intCast(target.height),
    };

    if (self.interop_ready) {
        const resized = self.interop.resize(
            self.size.width,
            self.size.height,
        );
        const presented = self.interop.presentClear(self.clear_color);
        if (self.present_calls <= 8 or !presented) {
            log.info(
                "present call={} size={}x{} resized={} presented={} clear={any}",
                .{
                    self.present_calls,
                    self.size.width,
                    self.size.height,
                    resized,
                    presented,
                    self.clear_color,
                },
            );
        }
    }
}

pub fn presentLastTarget(self: *D3D11) !void {
    self.present_last_calls += 1;
    if (self.last_target) |target| {
        self.size = .{
            .width = @intCast(target.width),
            .height = @intCast(target.height),
        };
    }

    if (!self.interop_ready) return;
    if (self.size.width == 0 or self.size.height == 0) return;

    const resized = self.interop.resize(
        self.size.width,
        self.size.height,
    );
    const presented = self.interop.presentClear(self.clear_color);
    if (self.present_last_calls <= 8 or !presented) {
        log.info(
            "presentLastTarget call={} size={}x{} resized={} presented={} clear={any}",
            .{
                self.present_last_calls,
                self.size.width,
                self.size.height,
                resized,
                presented,
                self.clear_color,
            },
        );
    }
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

pub fn beginFrame(
    self: *const D3D11,
    renderer: *Renderer,
    target: *Target,
) !Frame {
    _ = self;
    return try Frame.begin(.{}, renderer, target);
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
    _ = self;
    return .{
        .target = .array,
        .usage = .dynamic_draw,
    };
}

pub const instanceBufferOptions = bufferOptions;
pub const uniformBufferOptions = bufferOptions;
pub const fgBufferOptions = bufferOptions;
pub const bgBufferOptions = bufferOptions;
pub const imageBufferOptions = bufferOptions;
pub const bgImageBufferOptions = bufferOptions;

pub inline fn textureOptions(self: D3D11) Texture.Options {
    _ = self;
    return .{
        .format = .rgba,
        .internal_format = .srgba,
        .target = .@"2D",
        .min_filter = .linear,
        .mag_filter = .linear,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    };
}

pub inline fn samplerOptions(self: D3D11) Sampler.Options {
    _ = self;
    return .{
        .min_filter = .linear,
        .mag_filter = .linear,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    };
}

pub const ImageTextureFormat = enum {
    gray,
    rgba,
    bgra,

    fn toPixelFormat(self: ImageTextureFormat) Texture.Format {
        return switch (self) {
            .gray => .red,
            .rgba => .rgba,
            .bgra => .bgra,
        };
    }
};

pub inline fn imageTextureOptions(
    self: D3D11,
    format: ImageTextureFormat,
    srgb: bool,
) Texture.Options {
    _ = self;
    return .{
        .format = format.toPixelFormat(),
        .internal_format = if (srgb) .srgba else .rgba,
        .target = .@"2D",
        .min_filter = .linear,
        .mag_filter = .linear,
        .wrap_s = .clamp_to_edge,
        .wrap_t = .clamp_to_edge,
    };
}

pub fn initAtlasTexture(
    self: *const D3D11,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    _ = self;
    const format: Texture.Format, const internal_format: Texture.InternalFormat = switch (atlas.format) {
        .grayscale => .{ .red, .red },
        // D3D11 scaffold ignores texture upload details; map BGR to BGRA-compatible placeholder.
        .bgr => .{ .bgra, .srgba },
        .bgra => .{ .bgra, .srgba },
    };
    return Texture.init(
        .{
            .format = format,
            .internal_format = internal_format,
            .target = .Rectangle,
            .min_filter = .nearest,
            .mag_filter = .nearest,
            .wrap_s = .clamp_to_edge,
            .wrap_t = .clamp_to_edge,
        },
        atlas.size,
        atlas.size,
        null,
    );
}
