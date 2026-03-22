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
const shaderpkg = @import("d3d11/shaders.zig");

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
frame_pixels: std.ArrayListUnmanaged(u8) = .{},
capture: Capture = .{},
compose_calls: usize = 0,

const Capture = struct {
    uniforms: ?BufferHandle = null,
    bg: ?BufferHandle = null,
    fg: ?BufferHandle = null,
    grayscale: ?Texture = null,
    color: ?Texture = null,
    instance_count: usize = 0,
};

pub const TextStepCapture = struct {
    uniforms: ?BufferHandle,
    fg: ?BufferHandle,
    bg: ?BufferHandle,
    grayscale: ?Texture,
    color: ?Texture,
    instance_count: usize,
};

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
    const initial_scale = currentContentScale(opts.rt_surface);
    if (interop_ready) {
        _ = interop.setCompositionScale(
            @floatCast(initial_scale.x),
            @floatCast(initial_scale.y),
        );
    }
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
        "initialized D3D11 scaffold swap_chain_panel={any} initial_clear={any} scale={d:.3}x{d:.3}",
        .{ swap_chain_panel, initial_clear_color, initial_scale.x, initial_scale.y },
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
    self.frame_pixels.deinit(self.alloc);
    if (self.interop_ready) {
        self.interop.deinit();
    }
    self.* = undefined;
}

pub fn drawFrameStart(self: *D3D11) void {
    self.capture = .{};
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
        const scale = self.updateInteropCompositionScale();
        const resized = self.interop.resize(
            self.size.width,
            self.size.height,
        );
        const composed = try self.composeFramePixels();
        const presented = self.interop.presentFrame(
            self.clear_color,
            composed,
            self.size.width,
            self.size.height,
        );
        if (self.present_calls <= 8 or !presented) {
            log.info(
                "present call={} size={}x{} scale={d:.3}x{d:.3} resized={} presented={} composed={} clear={any}",
                .{
                    self.present_calls,
                    self.size.width,
                    self.size.height,
                    scale.x,
                    scale.y,
                    resized,
                    presented,
                    composed != null,
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

    const scale = self.updateInteropCompositionScale();
    const resized = self.interop.resize(
        self.size.width,
        self.size.height,
    );
    const presented = self.interop.presentFrame(
        self.clear_color,
        null,
        self.size.width,
        self.size.height,
    );
    if (self.present_last_calls <= 8 or !presented) {
        log.info(
            "presentLastTarget call={} size={}x{} scale={d:.3}x{d:.3} resized={} presented={} clear={any}",
            .{
                self.present_last_calls,
                self.size.width,
                self.size.height,
                scale.x,
                scale.y,
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

fn currentContentScale(rt_surface: *apprt.Surface) apprt.ContentScale {
    return rt_surface.getContentScale() catch .{ .x = 1.0, .y = 1.0 };
}

fn updateInteropCompositionScale(self: *D3D11) apprt.ContentScale {
    const scale = currentContentScale(self.rt_surface);
    _ = self.interop.setCompositionScale(
        @floatCast(scale.x),
        @floatCast(scale.y),
    );
    return scale;
}

pub fn captureUniformBuffer(self: *D3D11, uniforms: BufferHandle) void {
    self.capture.uniforms = uniforms;
}

pub fn captureBgBuffer(self: *D3D11, bg: BufferHandle) void {
    self.capture.bg = bg;
}

pub fn captureTextStep(self: *D3D11, capture: TextStepCapture) void {
    if (capture.uniforms) |u| self.capture.uniforms = u;
    if (capture.bg) |b| self.capture.bg = b;
    self.capture.fg = capture.fg;
    self.capture.grayscale = capture.grayscale;
    self.capture.color = capture.color;
    self.capture.instance_count = capture.instance_count;
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

fn composeFramePixels(self: *D3D11) !?[]const u8 {
    const uniforms_h = self.capture.uniforms orelse return null;
    const uniforms = loadUniforms(uniforms_h) orelse return null;
    const fg_h = self.capture.fg orelse return null;
    if (fg_h.len == 0 or fg_h.bytes.len == 0) return null;

    const width = self.size.width;
    const height = self.size.height;
    if (width == 0 or height == 0) return null;

    const px_count: usize = @as(usize, width) * @as(usize, height);
    const byte_count = px_count * 4;
    try self.frame_pixels.resize(self.alloc, byte_count);
    const pixels = self.frame_pixels.items;

    const global_bg = uniforms.bg_color;
    const global_bgra = premultipliedBGRA(.{
        global_bg[0],
        global_bg[1],
        global_bg[2],
        global_bg[3],
    });

    var i: usize = 0;
    while (i < byte_count) : (i += 4) {
        pixels[i + 0] = global_bgra[0];
        pixels[i + 1] = global_bgra[1];
        pixels[i + 2] = global_bgra[2];
        pixels[i + 3] = 0xFF;
    }

    const cols: usize = uniforms.grid_size[0];
    const rows: usize = uniforms.grid_size[1];
    const cell_w: i32 = @max(1, @as(i32, @intFromFloat(@round(uniforms.cell_size[0]))));
    const cell_h: i32 = @max(1, @as(i32, @intFromFloat(@round(uniforms.cell_size[1]))));
    const pad_left: i32 = @as(i32, @intFromFloat(@round(uniforms.grid_padding[3])));
    const pad_top: i32 = @as(i32, @intFromFloat(@round(uniforms.grid_padding[0])));

    if (self.capture.bg) |bg_h| {
        const bg_cells = cellBgBytes(bg_h);
        const bg_count = @min(cols * rows, bg_cells.len / 4);
        for (0..bg_count) |idx| {
            const cx = idx % cols;
            const cy = idx / cols;
            const bg = .{
                bg_cells[idx * 4 + 0],
                bg_cells[idx * 4 + 1],
                bg_cells[idx * 4 + 2],
                bg_cells[idx * 4 + 3],
            };
            if (bg[3] == 0) continue;

            const x0 = pad_left + @as(i32, @intCast(cx)) * cell_w;
            const y0 = pad_top + @as(i32, @intCast(cy)) * cell_h;
            fillRectBlend(
                pixels,
                @as(i32, @intCast(width)),
                @as(i32, @intCast(height)),
                x0,
                y0,
                cell_w,
                cell_h,
                premultipliedBGRA(bg),
            );
        }
    }

    const fg_cells = cellTextSlice(fg_h);
    const fg_count = @min(self.capture.instance_count, fg_cells.len);
    if (fg_count == 0) return pixels;

    const grayscale = self.capture.grayscale;
    const color = self.capture.color;
    for (fg_cells[0..fg_count]) |cell| {
        const glyph_w: i32 = @intCast(cell.glyph_size[0]);
        const glyph_h: i32 = @intCast(cell.glyph_size[1]);
        if (glyph_w <= 0 or glyph_h <= 0) continue;

        const base_x = pad_left +
            @as(i32, @intCast(cell.grid_pos[0])) * cell_w +
            cell.bearings[0];
        const base_y = pad_top +
            @as(i32, @intCast(cell.grid_pos[1])) * cell_h +
            (cell_h - cell.bearings[1]);

        switch (cell.atlas) {
            .grayscale => if (grayscale) |atlas| {
                drawGrayscaleGlyph(
                    pixels,
                    @as(i32, @intCast(width)),
                    @as(i32, @intCast(height)),
                    atlas,
                    cell,
                    base_x,
                    base_y,
                );
            },
            .color => if (color) |atlas| {
                drawColorGlyph(
                    pixels,
                    @as(i32, @intCast(width)),
                    @as(i32, @intCast(height)),
                    atlas,
                    cell,
                    base_x,
                    base_y,
                );
            },
        }
    }

    self.compose_calls += 1;
    if (self.compose_calls <= 8) {
        var non_bg_pixels: usize = 0;
        var px_i: usize = 0;
        while (px_i < byte_count) : (px_i += 4) {
            if (pixels[px_i + 0] != global_bgra[0] or
                pixels[px_i + 1] != global_bgra[1] or
                pixels[px_i + 2] != global_bgra[2])
            {
                non_bg_pixels += 1;
            }
        }
        log.info(
            "composed text frame call={} fg_count={} non_bg_pixels={} grid={}x{} cell={}x{}",
            .{
                self.compose_calls,
                fg_count,
                non_bg_pixels,
                cols,
                rows,
                cell_w,
                cell_h,
            },
        );
    }

    return pixels;
}

fn loadUniforms(handle: BufferHandle) ?shaderpkg.Uniforms {
    if (handle.bytes.len < @sizeOf(shaderpkg.Uniforms)) return null;
    const ptr: *const shaderpkg.Uniforms = @ptrCast(@alignCast(handle.bytes.ptr));
    return ptr.*;
}

fn cellBgBytes(handle: BufferHandle) []const u8 {
    if (handle.stride != @sizeOf(shaderpkg.CellBg)) return &.{};
    return handle.bytes;
}

fn cellTextSlice(handle: BufferHandle) []const shaderpkg.CellText {
    if (handle.stride != @sizeOf(shaderpkg.CellText)) return &.{};
    if (handle.bytes.len < @sizeOf(shaderpkg.CellText)) return &.{};
    const count = @min(handle.len, handle.bytes.len / @sizeOf(shaderpkg.CellText));
    if (count == 0) return &.{};
    const ptr: [*]const shaderpkg.CellText = @ptrCast(@alignCast(handle.bytes.ptr));
    return ptr[0..count];
}

fn fillRectBlend(
    pixels: []u8,
    width: i32,
    height: i32,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    src_bgra: [4]u8,
) void {
    if (w <= 0 or h <= 0) return;
    const x0 = @max(0, x);
    const y0 = @max(0, y);
    const x1 = @min(width, x + w);
    const y1 = @min(height, y + h);
    if (x1 <= x0 or y1 <= y0) return;

    var py = y0;
    while (py < y1) : (py += 1) {
        var px = x0;
        while (px < x1) : (px += 1) {
            blendPixel(pixels, width, px, py, src_bgra);
        }
    }
}

fn drawGrayscaleGlyph(
    pixels: []u8,
    width: i32,
    height: i32,
    atlas: Texture,
    cell: shaderpkg.CellText,
    base_x: i32,
    base_y: i32,
) void {
    if (atlas.format != .red) return;
    if (atlas.width == 0 or atlas.height == 0) return;

    const glyph_w: i32 = @intCast(cell.glyph_size[0]);
    const glyph_h: i32 = @intCast(cell.glyph_size[1]);
    const src_x0: i32 = @intCast(cell.glyph_pos[0]);
    const src_y0: i32 = @intCast(cell.glyph_pos[1]);

    var gy: i32 = 0;
    while (gy < glyph_h) : (gy += 1) {
        const sy = src_y0 + gy;
        const dy = base_y + gy;
        if (dy < 0 or dy >= height) continue;
        if (sy < 0 or sy >= @as(i32, @intCast(atlas.height))) continue;

        var gx: i32 = 0;
        while (gx < glyph_w) : (gx += 1) {
            const sx = src_x0 + gx;
            const dx = base_x + gx;
            if (dx < 0 or dx >= width) continue;
            if (sx < 0 or sx >= @as(i32, @intCast(atlas.width))) continue;

            const sidx = @as(usize, @intCast(sy)) * atlas.width + @as(usize, @intCast(sx));
            const mask_alpha = atlas.data[sidx];
            if (mask_alpha == 0) continue;

            const src_alpha: u32 = (@as(u32, mask_alpha) * @as(u32, cell.color[3])) / 255;
            if (src_alpha == 0) continue;
            const src_bgra = .{
                @as(u8, @intCast((@as(u32, cell.color[2]) * src_alpha) / 255)),
                @as(u8, @intCast((@as(u32, cell.color[1]) * src_alpha) / 255)),
                @as(u8, @intCast((@as(u32, cell.color[0]) * src_alpha) / 255)),
                @as(u8, @intCast(src_alpha)),
            };
            blendPixel(pixels, width, dx, dy, src_bgra);
        }
    }
}

fn drawColorGlyph(
    pixels: []u8,
    width: i32,
    height: i32,
    atlas: Texture,
    cell: shaderpkg.CellText,
    base_x: i32,
    base_y: i32,
) void {
    if (atlas.format != .bgra and atlas.format != .rgba) return;
    if (atlas.width == 0 or atlas.height == 0) return;
    const bpp = Texture.bytesPerPixel(atlas.format);
    if (bpp != 4) return;

    const glyph_w: i32 = @intCast(cell.glyph_size[0]);
    const glyph_h: i32 = @intCast(cell.glyph_size[1]);
    const src_x0: i32 = @intCast(cell.glyph_pos[0]);
    const src_y0: i32 = @intCast(cell.glyph_pos[1]);

    var gy: i32 = 0;
    while (gy < glyph_h) : (gy += 1) {
        const sy = src_y0 + gy;
        const dy = base_y + gy;
        if (dy < 0 or dy >= height) continue;
        if (sy < 0 or sy >= @as(i32, @intCast(atlas.height))) continue;

        var gx: i32 = 0;
        while (gx < glyph_w) : (gx += 1) {
            const sx = src_x0 + gx;
            const dx = base_x + gx;
            if (dx < 0 or dx >= width) continue;
            if (sx < 0 or sx >= @as(i32, @intCast(atlas.width))) continue;

            const sidx = (@as(usize, @intCast(sy)) * atlas.width + @as(usize, @intCast(sx))) * 4;
            const src = if (atlas.format == .bgra)
                [4]u8{
                    atlas.data[sidx + 0],
                    atlas.data[sidx + 1],
                    atlas.data[sidx + 2],
                    atlas.data[sidx + 3],
                }
            else
                [4]u8{
                    atlas.data[sidx + 2],
                    atlas.data[sidx + 1],
                    atlas.data[sidx + 0],
                    atlas.data[sidx + 3],
                };
            if (src[3] == 0) continue;
            blendPixel(pixels, width, dx, dy, src);
        }
    }
}

fn blendPixel(
    pixels: []u8,
    width: i32,
    x: i32,
    y: i32,
    src_bgra: [4]u8,
) void {
    const idx = (@as(usize, @intCast(y)) * @as(usize, @intCast(width)) + @as(usize, @intCast(x))) * 4;
    const src_a: u32 = src_bgra[3];
    if (src_a == 255) {
        pixels[idx + 0] = src_bgra[0];
        pixels[idx + 1] = src_bgra[1];
        pixels[idx + 2] = src_bgra[2];
        pixels[idx + 3] = 0xFF;
        return;
    }

    const inv_a: u32 = 255 - src_a;
    pixels[idx + 0] = @as(u8, @intCast(@as(u32, src_bgra[0]) + (@as(u32, pixels[idx + 0]) * inv_a) / 255));
    pixels[idx + 1] = @as(u8, @intCast(@as(u32, src_bgra[1]) + (@as(u32, pixels[idx + 1]) * inv_a) / 255));
    pixels[idx + 2] = @as(u8, @intCast(@as(u32, src_bgra[2]) + (@as(u32, pixels[idx + 2]) * inv_a) / 255));
    pixels[idx + 3] = 0xFF;
}

fn premultipliedBGRA(rgba: [4]u8) [4]u8 {
    const a: u32 = rgba[3];
    return .{
        @as(u8, @intCast((@as(u32, rgba[2]) * a) / 255)),
        @as(u8, @intCast((@as(u32, rgba[1]) * a) / 255)),
        @as(u8, @intCast((@as(u32, rgba[0]) * a) / 255)),
        rgba[3],
    };
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
