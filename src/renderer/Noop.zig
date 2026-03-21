//! Graphics API wrapper for no-op rendering.
pub const Noop = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const apprt = @import("../apprt.zig");
const configpkg = @import("../config.zig");
const font = @import("../font/main.zig");
const rendererpkg = @import("../renderer.zig");
const shadertoy = @import("shadertoy.zig");
const Renderer = rendererpkg.GenericRenderer(Noop);

const SurfaceSize = struct {
    width: u32,
    height: u32,
};

pub const GraphicsAPI = Noop;
pub const Target = @import("noop/Target.zig");
pub const Frame = @import("noop/Frame.zig");
pub const RenderPass = @import("noop/RenderPass.zig");
pub const Pipeline = @import("noop/Pipeline.zig");
const bufferpkg = @import("noop/buffer.zig");
pub const Buffer = bufferpkg.Buffer;
pub const BufferHandle = bufferpkg.Handle;
pub const Sampler = @import("noop/Sampler.zig");
pub const Texture = @import("noop/Texture.zig");
pub const shaders = @import("noop/shaders.zig");
pub const api = @import("noop/api.zig");

pub const custom_shader_target: shadertoy.Target = .glsl;
pub const custom_shader_y_is_down = false;

/// Single buffering is enough for noop.
pub const swap_chain_count = 1;

pub const BufferTarget = enum {
    array,
};

pub const BufferUsage = enum {
    dynamic_draw,
};

alloc: Allocator,
blending: configpkg.Config.AlphaBlending,
last_target: ?Target = null,
size: SurfaceSize = .{ .width = 0, .height = 0 },

pub fn init(alloc: Allocator, opts: rendererpkg.Options) error{}!Noop {
    return .{
        .alloc = alloc,
        .blending = opts.config.blending,
    };
}

pub fn deinit(self: *Noop) void {
    self.* = undefined;
}

pub fn drawFrameStart(self: *Noop) void {
    _ = self;
}

pub fn drawFrameEnd(self: *Noop) void {
    _ = self;
}

pub fn initShaders(
    self: *const Noop,
    alloc: Allocator,
    custom_shaders: []const [:0]const u8,
) !shaders.Shaders {
    _ = self;
    return try shaders.Shaders.init(alloc, custom_shaders);
}

pub fn surfaceSize(self: *const Noop) !SurfaceSize {
    return self.size;
}

pub fn initTarget(self: *const Noop, width: usize, height: usize) !Target {
    return Target.init(.{
        .width = width,
        .height = height,
        .internal_format = if (self.blending.isLinear()) .srgba else .rgba,
    });
}

pub fn present(self: *Noop, target: Target) !void {
    self.last_target = target;
    self.size = .{
        .width = @intCast(target.width),
        .height = @intCast(target.height),
    };
}

pub fn presentLastTarget(self: *Noop) !void {
    if (self.last_target) |target| {
        self.size = .{
            .width = @intCast(target.width),
            .height = @intCast(target.height),
        };
    }
}

pub fn beginFrame(
    self: *const Noop,
    renderer: *Renderer,
    target: *Target,
) !Frame {
    _ = self;
    return try Frame.begin(.{}, renderer, target);
}

pub fn surfaceInit(surface: *apprt.Surface) !void {
    _ = surface;
}

pub fn finalizeSurfaceInit(self: *const Noop, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

pub fn threadEnter(self: *const Noop, surface: *apprt.Surface) !void {
    _ = self;
    _ = surface;
}

pub fn threadExit(self: *const Noop) void {
    _ = self;
}

pub fn loopEnter(self: *const Noop) void {
    _ = self;
}

pub fn loopExit(self: *const Noop) void {
    _ = self;
}

pub fn displayRealized(self: *Noop) void {
    _ = self;
}

pub fn displayUnrealized(self: *Noop) void {
    _ = self;
}

pub inline fn bufferOptions(self: Noop) bufferpkg.Options {
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

pub inline fn textureOptions(self: Noop) Texture.Options {
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

pub inline fn samplerOptions(self: Noop) Sampler.Options {
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
    self: Noop,
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
    self: *const Noop,
    atlas: *const font.Atlas,
) Texture.Error!Texture {
    _ = self;
    const format: Texture.Format, const internal_format: Texture.InternalFormat = switch (atlas.format) {
        .grayscale => .{ .red, .red },
        // Noop backend ignores texture upload details; map BGR to BGRA-compatible placeholder.
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
