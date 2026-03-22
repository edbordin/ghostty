const builtin = @import("builtin");
const std = @import("std");

const win32 = if (builtin.os.tag == .windows) @import("win32").everything else struct {};
const win32ext = if (builtin.os.tag == .windows) @import("win32ext.zig") else struct {};
const swapchainpanel = if (builtin.os.tag == .windows) @import("swap_chain_panel.zig") else struct {
    pub fn setSwapChain(swap_chain_panel: *anyopaque, swap_chain: *anyopaque) bool {
        _ = swap_chain_panel;
        _ = swap_chain;
        return false;
    }
};
const textinterop = if (builtin.os.tag == .windows) @import("interop_text.zig") else struct {
    pub const UniformPrefix = extern struct {
        projection: [16]f32,
        screen_size: [2]f32,
        cell_size: [2]f32,
    };

    pub fn ensureTextPipeline(self: anytype) bool {
        _ = self;
        return false;
    }

    pub fn updateTextConstants(self: anytype, uniforms: []const u8) bool {
        _ = self;
        _ = uniforms;
        return false;
    }

    pub fn updateInstanceBuffer(
        self: anytype,
        cells: []const u8,
        stride: u32,
        count: u32,
    ) bool {
        _ = self;
        _ = cells;
        _ = stride;
        _ = count;
        return false;
    }

    pub fn updateAtlas(self: anytype, atlas: anytype, data: anytype) bool {
        _ = self;
        _ = atlas;
        _ = data;
        return false;
    }

    pub fn releaseTextPipeline(self: anytype) void {
        _ = self;
    }
};

pub const AtlasFormat = enum {
    red,
    rgba,
    bgra,
};

pub const AtlasData = struct {
    pixels: []const u8,
    width: u32,
    height: u32,
    format: AtlasFormat,
};

pub const TextFrameInput = struct {
    clear_color: [4]f32,
    uniforms: []const u8,
    cells: []const u8,
    cell_stride: u32,
    instance_count: u32,
    grayscale: ?AtlasData = null,
    color: ?AtlasData = null,
};

pub const State = if (builtin.os.tag == .windows) struct {
    const AtlasTexture = struct {
        texture: ?*win32.ID3D11Texture2D = null,
        view: ?*win32.ID3D11ShaderResourceView = null,
        width: u32 = 0,
        height: u32 = 0,
        format: AtlasFormat = .red,
    };

    device: ?*win32.ID3D11Device = null,
    context: ?*win32.ID3D11DeviceContext = null,
    swap_chain: ?*win32.IDXGISwapChain1 = null,
    swap_chain2: ?*win32.IDXGISwapChain2 = null,
    render_target: ?*win32.ID3D11RenderTargetView = null,
    text_vs: ?*win32.ID3D11VertexShader = null,
    text_ps: ?*win32.ID3D11PixelShader = null,
    text_input_layout: ?*win32.ID3D11InputLayout = null,
    text_blend: ?*win32.ID3D11BlendState = null,
    text_constants: ?*win32.ID3D11Buffer = null,
    text_instances: ?*win32.ID3D11Buffer = null,
    text_instance_capacity: u32 = 0,
    atlas_gray: AtlasTexture = .{},
    atlas_color: AtlasTexture = .{},
    text_ready: bool = false,
    composition_scale_x: f32 = 1.0,
    composition_scale_y: f32 = 1.0,
    width: u32 = 0,
    height: u32 = 0,

    pub fn init(
        self: *State,
        swap_chain_panel: ?*anyopaque,
        width: u32,
        height: u32,
    ) bool {
        if (swap_chain_panel == null) return false;
        const safe_width = if (width > 0) width else 1;
        const safe_height = if (height > 0) height else 1;

        if (!self.createDevice()) {
            self.deinit();
            return false;
        }

        if (!self.createSwapChainForPanel(swap_chain_panel, safe_width, safe_height)) {
            self.deinit();
            return false;
        }

        return true;
    }

    pub fn deinit(self: *State) void {
        textinterop.releaseTextPipeline(self);
        win32ext.releaseAndNull(win32.ID3D11RenderTargetView, &self.render_target);
        win32ext.releaseAndNull(win32.IDXGISwapChain2, &self.swap_chain2);
        win32ext.releaseAndNull(win32.IDXGISwapChain1, &self.swap_chain);
        win32ext.releaseAndNull(win32.ID3D11DeviceContext, &self.context);
        win32ext.releaseAndNull(win32.ID3D11Device, &self.device);
        self.width = 0;
        self.height = 0;
    }

    pub fn setCompositionScale(self: *State, scale_x: f32, scale_y: f32) bool {
        const safe_x = sanitizeScale(scale_x);
        const safe_y = sanitizeScale(scale_y);
        if (self.composition_scale_x == safe_x and self.composition_scale_y == safe_y) {
            return true;
        }

        self.composition_scale_x = safe_x;
        self.composition_scale_y = safe_y;
        return self.applyCompositionScaleTransform();
    }

    pub fn resize(self: *State, width: u32, height: u32) bool {
        if (self.swap_chain == null or self.context == null or width == 0 or height == 0) {
            return false;
        }

        if (self.width == width and self.height == height and self.render_target != null) {
            return true;
        }

        var null_target: ?*win32.ID3D11RenderTargetView = null;
        self.context.?.OMSetRenderTargets(
            1,
            @ptrCast(&null_target),
            null,
        );

        win32ext.releaseAndNull(win32.ID3D11RenderTargetView, &self.render_target);

        const hr = self.swap_chain.?.IDXGISwapChain.ResizeBuffers(
            0,
            width,
            height,
            win32.DXGI_FORMAT_UNKNOWN,
            0,
        );
        if (hr < 0) return false;

        _ = self.applyCompositionScaleTransform();
        if (!self.createRenderTarget()) return false;

        self.width = width;
        self.height = height;
        return true;
    }

    pub fn presentClear(self: *State, clear_color: [4]f32) bool {
        if (!self.clearRenderTarget(clear_color)) return false;
        return self.presentOnly();
    }

    pub fn clearRenderTarget(self: *State, clear_color: [4]f32) bool {
        if (self.context == null or self.render_target == null) return false;
        var target = self.render_target.?;
        self.context.?.OMSetRenderTargets(
            1,
            @ptrCast(&target),
            null,
        );
        self.context.?.ClearRenderTargetView(
            target,
            @ptrCast(&clear_color),
        );
        return true;
    }

    pub fn presentFrame(
        self: *State,
        clear_color: [4]f32,
        pixels: ?[]const u8,
        width: u32,
        height: u32,
    ) bool {
        _ = pixels;
        _ = width;
        _ = height;
        return self.presentClear(clear_color);
    }

    pub fn presentOnly(self: *State) bool {
        if (self.swap_chain == null) return false;
        const hr = self.swap_chain.?.IDXGISwapChain.Present(1, 0);
        return hr >= 0 or hr == win32.DXGI_STATUS_OCCLUDED;
    }

    pub fn renderTextFrame(self: *State, input: TextFrameInput) bool {
        if (!self.clearRenderTarget(input.clear_color)) return false;
        if (input.instance_count > 0 and !self.drawTextFrame(input)) return false;
        return self.presentOnly();
    }

    pub fn drawTextFrame(self: *State, input: TextFrameInput) bool {
        if (self.context == null or self.swap_chain == null or self.render_target == null) return false;
        if (input.instance_count == 0) return true;
        if (input.cell_stride == 0) return false;
        if (input.uniforms.len < @sizeOf(textinterop.UniformPrefix)) return false;
        if (input.cells.len < @as(usize, input.cell_stride) * @as(usize, input.instance_count)) return false;
        const grayscale = input.grayscale orelse return false;
        if (grayscale.width == 0 or grayscale.height == 0) return false;

        if (!textinterop.ensureTextPipeline(self)) return false;
        if (!textinterop.updateTextConstants(self, input.uniforms)) return false;
        if (!textinterop.updateInstanceBuffer(self, input.cells, input.cell_stride, input.instance_count)) return false;
        if (!textinterop.updateAtlas(self, &self.atlas_gray, grayscale)) return false;
        if (input.color) |atlas| {
            if (!textinterop.updateAtlas(self, &self.atlas_color, atlas)) return false;
        }

        var target = self.render_target.?;
        self.context.?.OMSetRenderTargets(1, @ptrCast(&target), null);

        var viewport = win32.D3D11_VIEWPORT{
            .TopLeftX = 0,
            .TopLeftY = 0,
            .Width = @floatFromInt(self.width),
            .Height = @floatFromInt(self.height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };
        self.context.?.RSSetViewports(1, @ptrCast(&viewport));

        self.context.?.IASetInputLayout(self.text_input_layout);
        self.context.?.IASetPrimitiveTopology(win32.D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);

        var vb = self.text_instances;
        const strides = [_]u32{input.cell_stride};
        const offsets = [_]u32{0};
        self.context.?.IASetVertexBuffers(
            0,
            1,
            @ptrCast(&vb),
            strides[0..].ptr,
            offsets[0..].ptr,
        );

        self.context.?.VSSetShader(self.text_vs, null, 0);
        self.context.?.PSSetShader(self.text_ps, null, 0);

        var cb = self.text_constants;
        self.context.?.VSSetConstantBuffers(0, 1, @ptrCast(&cb));

        var srvs = [_]?*win32.ID3D11ShaderResourceView{
            self.atlas_gray.view,
            self.atlas_color.view,
        };
        self.context.?.PSSetShaderResources(0, srvs.len, srvs[0..].ptr);

        const blend_factor = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
        self.context.?.OMSetBlendState(
            self.text_blend,
            &blend_factor[0],
            0xFFFF_FFFF,
        );

        self.context.?.DrawInstanced(4, input.instance_count, 0, 0);

        var null_srvs = [_]?*win32.ID3D11ShaderResourceView{ null, null };
        self.context.?.PSSetShaderResources(0, null_srvs.len, null_srvs[0..].ptr);

        return true;
    }

    fn createDevice(self: *State) bool {
        const levels = [_]win32.D3D_FEATURE_LEVEL{
            win32.D3D_FEATURE_LEVEL_11_1,
            win32.D3D_FEATURE_LEVEL_11_0,
            win32.D3D_FEATURE_LEVEL_10_1,
            win32.D3D_FEATURE_LEVEL_10_0,
        };

        const fallback_levels = [_]win32.D3D_FEATURE_LEVEL{
            win32.D3D_FEATURE_LEVEL_11_0,
            win32.D3D_FEATURE_LEVEL_10_1,
            win32.D3D_FEATURE_LEVEL_10_0,
        };

        var flags: win32.D3D11_CREATE_DEVICE_FLAG = .{ .BGRA_SUPPORT = 1 };
        if (builtin.mode == .Debug) flags.DEBUG = 1;

        var device: ?*win32.ID3D11Device = null;
        var context: ?*win32.ID3D11DeviceContext = null;
        var created_level: win32.D3D_FEATURE_LEVEL = win32.D3D_FEATURE_LEVEL_11_0;

        var hr = win32.D3D11CreateDevice(
            null,
            win32.D3D_DRIVER_TYPE_HARDWARE,
            null,
            flags,
            levels[0..].ptr,
            levels.len,
            win32.D3D11_SDK_VERSION,
            @ptrCast(&device),
            &created_level,
            @ptrCast(&context),
        );

        if (hr == win32.E_INVALIDARG) {
            hr = win32.D3D11CreateDevice(
                null,
                win32.D3D_DRIVER_TYPE_HARDWARE,
                null,
                flags,
                fallback_levels[0..].ptr,
                fallback_levels.len,
                win32.D3D11_SDK_VERSION,
                @ptrCast(&device),
                &created_level,
                @ptrCast(&context),
            );
        }

        if (hr < 0 and flags.DEBUG == 1) {
            flags.DEBUG = 0;
            hr = win32.D3D11CreateDevice(
                null,
                win32.D3D_DRIVER_TYPE_HARDWARE,
                null,
                flags,
                levels[0..].ptr,
                levels.len,
                win32.D3D11_SDK_VERSION,
                @ptrCast(&device),
                &created_level,
                @ptrCast(&context),
            );

            if (hr == win32.E_INVALIDARG) {
                hr = win32.D3D11CreateDevice(
                    null,
                    win32.D3D_DRIVER_TYPE_HARDWARE,
                    null,
                    flags,
                    fallback_levels[0..].ptr,
                    fallback_levels.len,
                    win32.D3D11_SDK_VERSION,
                    @ptrCast(&device),
                    &created_level,
                    @ptrCast(&context),
                );
            }
        }

        if (hr < 0) {
            hr = win32.D3D11CreateDevice(
                null,
                win32.D3D_DRIVER_TYPE_WARP,
                null,
                flags,
                levels[0..].ptr,
                levels.len,
                win32.D3D11_SDK_VERSION,
                @ptrCast(&device),
                &created_level,
                @ptrCast(&context),
            );

            if (hr == win32.E_INVALIDARG) {
                hr = win32.D3D11CreateDevice(
                    null,
                    win32.D3D_DRIVER_TYPE_WARP,
                    null,
                    flags,
                    fallback_levels[0..].ptr,
                    fallback_levels.len,
                    win32.D3D11_SDK_VERSION,
                    @ptrCast(&device),
                    &created_level,
                    @ptrCast(&context),
                );
            }
        }

        if (hr < 0 or device == null or context == null) return false;
        self.device = device;
        self.context = context;
        return true;
    }

    fn createSwapChainForPanel(
        self: *State,
        swap_chain_panel: ?*anyopaque,
        width: u32,
        height: u32,
    ) bool {
        if (self.device == null or swap_chain_panel == null) return false;

        const dxgi_device = win32ext.queryInterface(self.device.?, win32.IDXGIDevice);
        defer _ = dxgi_device.IUnknown.Release();

        var adapter: *win32.IDXGIAdapter = undefined;
        const adapter_hr = dxgi_device.GetAdapter(&adapter);
        if (adapter_hr < 0) return false;
        defer _ = adapter.IUnknown.Release();

        var factory_opaque: *anyopaque = undefined;
        const factory_hr = adapter.IDXGIObject.GetParent(
            win32.IID_IDXGIFactory2,
            &factory_opaque,
        );
        if (factory_hr < 0) return false;

        const factory: *win32.IDXGIFactory2 = @ptrCast(@alignCast(factory_opaque));
        defer _ = factory.IUnknown.Release();

        const desc: win32.DXGI_SWAP_CHAIN_DESC1 = .{
            .Width = width,
            .Height = height,
            .Format = win32.DXGI_FORMAT_B8G8R8A8_UNORM,
            .Stereo = win32.FALSE,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .Scaling = win32.DXGI_SCALING_STRETCH,
            .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
            .AlphaMode = win32.DXGI_ALPHA_MODE_PREMULTIPLIED,
            .Flags = 0,
        };

        var swap_chain: *win32.IDXGISwapChain1 = undefined;
        const create_hr = factory.CreateSwapChainForComposition(
            &self.device.?.IUnknown,
            &desc,
            null,
            &swap_chain,
        );
        if (create_hr < 0) return false;

        var swap_chain2: ?*win32.IDXGISwapChain2 = null;
        const swap_chain2_hr = swap_chain.IUnknown.QueryInterface(
            win32.IID_IDXGISwapChain2,
            @ptrCast(&swap_chain2),
        );
        if (swap_chain2_hr < 0 or swap_chain2 == null) {
            _ = swap_chain.IUnknown.Release();
            return false;
        }

        if (!swapchainpanel.setSwapChain(swap_chain_panel.?, swap_chain)) {
            _ = swap_chain2.?.IUnknown.Release();
            _ = swap_chain.IUnknown.Release();
            return false;
        }

        self.swap_chain = swap_chain;
        self.swap_chain2 = swap_chain2;
        self.width = width;
        self.height = height;
        _ = self.applyCompositionScaleTransform();
        return self.createRenderTarget();
    }

    fn createRenderTarget(self: *State) bool {
        if (self.device == null or self.swap_chain == null) return false;

        var back_buffer: *win32.ID3D11Texture2D = undefined;
        const hr = self.swap_chain.?.IDXGISwapChain.GetBuffer(
            0,
            win32.IID_ID3D11Texture2D,
            @ptrCast(&back_buffer),
        );
        if (hr < 0) return false;
        defer _ = back_buffer.IUnknown.Release();

        var rtv: ?*win32.ID3D11RenderTargetView = null;
        const rtv_hr = self.device.?.CreateRenderTargetView(
            @ptrCast(back_buffer),
            null,
            @ptrCast(&rtv),
        );
        if (rtv_hr < 0 or rtv == null) return false;
        self.render_target = rtv;
        return true;
    }

    fn applyCompositionScaleTransform(self: *State) bool {
        if (self.swap_chain2 == null) return false;

        // SwapChainPanel/WinUI applies composition scaling; apply the inverse
        // so Ghostty renders at full native resolution:
        // https://stackoverflow.com/a/42543636
        const matrix: win32.DXGI_MATRIX_3X2_F = .{
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
} else struct {
    pub fn init(
        self: *State,
        swap_chain_panel: ?*anyopaque,
        width: u32,
        height: u32,
    ) bool {
        _ = self;
        _ = swap_chain_panel;
        _ = width;
        _ = height;
        return false;
    }

    pub fn deinit(self: *State) void {
        _ = self;
    }

    pub fn resize(self: *State, width: u32, height: u32) bool {
        _ = self;
        _ = width;
        _ = height;
        return false;
    }

    pub fn presentClear(self: *State, clear_color: [4]f32) bool {
        _ = self;
        _ = clear_color;
        return false;
    }

    pub fn clearRenderTarget(self: *State, clear_color: [4]f32) bool {
        _ = self;
        _ = clear_color;
        return false;
    }

    pub fn presentFrame(
        self: *State,
        clear_color: [4]f32,
        pixels: ?[]const u8,
        width: u32,
        height: u32,
    ) bool {
        _ = self;
        _ = clear_color;
        _ = pixels;
        _ = width;
        _ = height;
        return false;
    }

    pub fn presentOnly(self: *State) bool {
        _ = self;
        return false;
    }

    pub fn renderTextFrame(self: *State, input: TextFrameInput) bool {
        _ = self;
        _ = input;
        return false;
    }

    pub fn drawTextFrame(self: *State, input: TextFrameInput) bool {
        _ = self;
        _ = input;
        return false;
    }

    pub fn setCompositionScale(self: *State, scale_x: f32, scale_y: f32) bool {
        _ = self;
        _ = scale_x;
        _ = scale_y;
        return false;
    }
};
