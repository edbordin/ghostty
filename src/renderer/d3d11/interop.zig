const builtin = @import("builtin");
const std = @import("std");

const win32 = if (builtin.os.tag == .windows) @import("win32").everything else struct {};
const win32ext = if (builtin.os.tag == .windows) @import("win32ext.zig") else struct {};

// TODO: Research whether zwindows offers a cleaner binding for
// ISwapChainPanelNative/SetSwapChain so this manual COM shape can go away.
const ISwapChainPanelNative = if (builtin.os.tag == .windows) extern union {
    pub const VTable = extern struct {
        base: win32.IUnknown.VTable,
        SetSwapChain: *const fn (
            self: *const ISwapChainPanelNative,
            swap_chain: ?*win32.IDXGISwapChain,
        ) callconv(.winapi) win32.HRESULT,
    };

    vtable: *const VTable,
    IUnknown: win32.IUnknown,

    pub fn SetSwapChain(
        self: *const ISwapChainPanelNative,
        swap_chain: ?*win32.IDXGISwapChain,
    ) callconv(.@"inline") win32.HRESULT {
        return self.vtable.SetSwapChain(self, swap_chain);
    }
} else struct {};

pub const State = if (builtin.os.tag == .windows) struct {
    device: ?*win32.ID3D11Device = null,
    context: ?*win32.ID3D11DeviceContext = null,
    swap_chain: ?*win32.IDXGISwapChain1 = null,
    swap_chain2: ?*win32.IDXGISwapChain2 = null,
    render_target: ?*win32.ID3D11RenderTargetView = null,
    frame_texture: ?*win32.ID3D11Texture2D = null,
    frame_texture_valid: bool = false,
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
        win32ext.releaseAndNull(win32.ID3D11Texture2D, &self.frame_texture);
        win32ext.releaseAndNull(win32.ID3D11RenderTargetView, &self.render_target);
        win32ext.releaseAndNull(win32.IDXGISwapChain2, &self.swap_chain2);
        win32ext.releaseAndNull(win32.IDXGISwapChain1, &self.swap_chain);
        win32ext.releaseAndNull(win32.ID3D11DeviceContext, &self.context);
        win32ext.releaseAndNull(win32.ID3D11Device, &self.device);
        self.frame_texture_valid = false;
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
        if (!self.ensureFrameTexture(width, height)) return false;

        self.width = width;
        self.height = height;
        return true;
    }

    pub fn presentClear(self: *State, clear_color: [4]f32) bool {
        return self.presentFrame(clear_color, null, self.width, self.height);
    }

    pub fn presentFrame(
        self: *State,
        clear_color: [4]f32,
        pixels: ?[]const u8,
        width: u32,
        height: u32,
    ) bool {
        if (self.context == null or self.swap_chain == null or self.render_target == null) {
            return false;
        }

        if (pixels) |data| {
            if (data.len > 0 and width > 0 and height > 0) {
                if (!self.uploadFramePixels(data, width, height)) return false;
            }
        }

        if (self.frame_texture_valid) {
            var null_target: ?*win32.ID3D11RenderTargetView = null;
            self.context.?.OMSetRenderTargets(
                1,
                @ptrCast(&null_target),
                null,
            );
            self.drawFrameTexture();
        } else {
            var target = self.render_target.?;
            self.context.?.OMSetRenderTargets(
                1,
                @ptrCast(&target),
                null,
            );
            self.context.?.ClearRenderTargetView(
                self.render_target.?,
                @ptrCast(&clear_color),
            );
        }

        const hr = self.swap_chain.?.IDXGISwapChain.Present(1, 0);
        return hr >= 0 or hr == win32.DXGI_STATUS_OCCLUDED;
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

        if (!setSwapChainOnPanel(swap_chain_panel.?, swap_chain)) {
            _ = swap_chain2.?.IUnknown.Release();
            _ = swap_chain.IUnknown.Release();
            return false;
        }

        self.swap_chain = swap_chain;
        self.swap_chain2 = swap_chain2;
        self.width = width;
        self.height = height;
        _ = self.applyCompositionScaleTransform();
        if (!self.createRenderTarget()) return false;
        return self.ensureFrameTexture(width, height);
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

    fn ensureFrameTexture(self: *State, width: u32, height: u32) bool {
        if (self.device == null or width == 0 or height == 0) return false;

        if (self.frame_texture) |tex| {
            var desc: win32.D3D11_TEXTURE2D_DESC = undefined;
            tex.GetDesc(&desc);
            if (desc.Width == width and desc.Height == height) return true;
        }

        win32ext.releaseAndNull(win32.ID3D11Texture2D, &self.frame_texture);
        self.frame_texture_valid = false;

        var texture: ?*win32.ID3D11Texture2D = null;
        const desc: win32.D3D11_TEXTURE2D_DESC = .{
            .Width = width,
            .Height = height,
            .MipLevels = 1,
            .ArraySize = 1,
            .Format = win32.DXGI_FORMAT_B8G8R8A8_UNORM,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .Usage = .DEFAULT,
            .BindFlags = .{},
            .CPUAccessFlags = .{},
            .MiscFlags = .{},
        };
        const texture_hr = self.device.?.CreateTexture2D(&desc, null, @ptrCast(&texture));
        if (texture_hr < 0 or texture == null) return false;
        self.frame_texture = texture;
        return true;
    }

    fn uploadFramePixels(self: *State, pixels: []const u8, width: u32, height: u32) bool {
        if (self.context == null) return false;
        if (!self.ensureFrameTexture(width, height)) return false;
        if (self.frame_texture == null) return false;

        const expected = @as(usize, width) * @as(usize, height) * 4;
        if (pixels.len < expected) return false;

        self.context.?.UpdateSubresource(
            @ptrCast(&self.frame_texture.?.ID3D11Resource),
            0,
            null,
            @ptrCast(pixels.ptr),
            width * 4,
            0,
        );
        self.frame_texture_valid = true;
        return true;
    }

    fn drawFrameTexture(self: *State) void {
        if (self.context == null or self.swap_chain == null or self.frame_texture == null) return;

        var back_buffer: *win32.ID3D11Texture2D = undefined;
        const hr = self.swap_chain.?.IDXGISwapChain.GetBuffer(
            0,
            win32.IID_ID3D11Texture2D,
            @ptrCast(&back_buffer),
        );
        if (hr < 0) return;
        defer _ = back_buffer.IUnknown.Release();

        self.context.?.CopyResource(
            @ptrCast(&back_buffer.ID3D11Resource),
            @ptrCast(&self.frame_texture.?.ID3D11Resource),
        );
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

    pub fn setCompositionScale(self: *State, scale_x: f32, scale_y: f32) bool {
        _ = self;
        _ = scale_x;
        _ = scale_y;
        return false;
    }
};

fn setSwapChainOnPanel(
    swap_chain_panel: *anyopaque,
    swap_chain: *win32.IDXGISwapChain1,
) bool {
    const panel_native: *ISwapChainPanelNative = @ptrCast(@alignCast(swap_chain_panel));
    const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(swap_chain);
    const hr = panel_native.SetSwapChain(swap_chain_base);
    return hr >= 0;
}
