//! Represents a D3D11 render target.
const Self = @This();

const zw = @import("zwindows");
const d3d = zw.d3d11;
const dxgi = zw.dxgi;
const win32ext = @import("win32ext.zig");

pub const Options = struct {
    device: *d3d.IDevice,
    width: usize,
    height: usize,
    format: dxgi.FORMAT,
};

width: usize,
height: usize,
format: dxgi.FORMAT,
device: *d3d.IDevice,
owns_resources: bool = true,
texture: ?*d3d.ITexture2D = null,
render_target: ?*d3d.IRenderTargetView = null,
shader_view: ?*d3d.IShaderResourceView = null,

pub fn init(opts: Options) !Self {
    var self: Self = .{
        .width = opts.width,
        .height = opts.height,
        .format = opts.format,
        .device = opts.device,
        .owns_resources = true,
        .texture = null,
        .render_target = null,
        .shader_view = null,
    };

    try self.initNativeResources(opts.device);
    errdefer self.deinitNativeResources();

    return self;
}

pub fn initSwapchain(
    device: *d3d.IDevice,
    render_target: *d3d.IRenderTargetView,
    width: usize,
    height: usize,
    format: dxgi.FORMAT,
) Self {
    return .{
        .width = width,
        .height = height,
        .format = format,
        .device = device,
        .owns_resources = false,
        .texture = null,
        .render_target = render_target,
        .shader_view = null,
    };
}

pub fn deinit(self: *Self) void {
    self.deinitNativeResources();
    self.* = undefined;
}

fn initNativeResources(self: *Self, device: *d3d.IDevice) !void {
    const format = self.format;

    const desc: d3d.TEXTURE2D_DESC = .{
        .Width = @intCast(self.width),
        .Height = @intCast(self.height),
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = format,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Usage = .DEFAULT,
        .BindFlags = .{
            .RENDER_TARGET = true,
            .SHADER_RESOURCE = true,
        },
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
    };

    var texture: ?*d3d.ITexture2D = null;
    if (device.CreateTexture2D(&desc, null, @ptrCast(&texture)) < 0 or texture == null) {
        return error.D3D11Failed;
    }
    errdefer win32ext.releaseAndNull(d3d.ITexture2D, &texture);

    var rtv: ?*d3d.IRenderTargetView = null;
    if (device.CreateRenderTargetView(
        @ptrCast(texture.?),
        null,
        @ptrCast(&rtv),
    ) < 0 or rtv == null) {
        return error.D3D11Failed;
    }
    errdefer win32ext.releaseAndNull(d3d.IRenderTargetView, &rtv);

    var srv: ?*d3d.IShaderResourceView = null;
    if (device.CreateShaderResourceView(
        @ptrCast(texture.?),
        null,
        @ptrCast(&srv),
    ) < 0 or srv == null) {
        return error.D3D11Failed;
    }

    self.texture = texture;
    self.render_target = rtv;
    self.shader_view = srv;
}

fn deinitNativeResources(self: *Self) void {
    if (!self.owns_resources) {
        self.texture = null;
        self.render_target = null;
        self.shader_view = null;
        return;
    }
    win32ext.releaseAndNull(d3d.IShaderResourceView, &self.shader_view);
    win32ext.releaseAndNull(d3d.IRenderTargetView, &self.render_target);
    win32ext.releaseAndNull(d3d.ITexture2D, &self.texture);
}
