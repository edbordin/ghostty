//! Wrapper for D3D11 textures.
const Self = @This();

const std = @import("std");
const zw = @import("zwindows");
const d3d = zw.d3d11;
const dxgi = zw.dxgi;

pub const Options = struct {
    device: *d3d.IDevice,
    context: *d3d.IDeviceContext,
    format: dxgi.FORMAT,
    render_target: bool = false,
};

pub const Error = error{
    OutOfMemory,
    D3D11Failed,
};

width: usize,
height: usize,
format: dxgi.FORMAT,
device: *d3d.IDevice,
context: *d3d.IDeviceContext,
texture: ?*d3d.ITexture2D = null,
shader_view: ?*d3d.IShaderResourceView = null,
render_target: ?*d3d.IRenderTargetView = null,
row_pitch: usize,

pub fn init(
    opts: Options,
    width: usize,
    height: usize,
    data: ?[]const u8,
) Error!Self {
    const row_pitch = width * bytesPerPixel(opts.format);

    // Always use .DEFAULT usage - can be updated with UpdateSubresource
    const desc: d3d.TEXTURE2D_DESC = .{
        .Width = @intCast(width),
        .Height = @intCast(height),
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = opts.format,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .Usage = .DEFAULT,
        .BindFlags = .{
            .SHADER_RESOURCE = true,
            .RENDER_TARGET = opts.render_target,
        },
        .CPUAccessFlags = .{},
        .MiscFlags = .{},
    };

    var texture: ?*d3d.ITexture2D = null;
    if (data) |src| {
        // Provide initial data via D3D11_SUBRESOURCE_DATA
        const subresource_data = d3d.SUBRESOURCE_DATA{
            .pSysMem = @ptrCast(src.ptr),
            .SysMemPitch = @intCast(row_pitch),
            .SysMemSlicePitch = 0,
        };
        const hr = opts.device.CreateTexture2D(&desc, &subresource_data, @ptrCast(&texture));
        if (hr < 0 or texture == null) return error.D3D11Failed;
    } else {
        const hr = opts.device.CreateTexture2D(&desc, null, @ptrCast(&texture));
        if (hr < 0 or texture == null) return error.D3D11Failed;
    }
    errdefer {
        if (texture) |t| _ = t.Release();
    }

    // Create shader resource view
    var view: ?*d3d.IShaderResourceView = null;
    const view_hr = opts.device.CreateShaderResourceView(
        @ptrCast(texture.?),
        null,
        @ptrCast(&view),
    );
    if (view_hr < 0 or view == null) return error.D3D11Failed;
    errdefer {
        if (view) |v| _ = v.Release();
    }

    var render_target: ?*d3d.IRenderTargetView = null;
    if (opts.render_target) {
        const rtv_hr = opts.device.CreateRenderTargetView(
            @ptrCast(texture.?),
            null,
            @ptrCast(&render_target),
        );
        if (rtv_hr < 0 or render_target == null) return error.D3D11Failed;
    }

    return .{
        .width = width,
        .height = height,
        .format = opts.format,
        .device = opts.device,
        .context = opts.context,
        .texture = texture,
        .shader_view = view,
        .render_target = render_target,
        .row_pitch = row_pitch,
    };
}

pub fn deinit(self: Self) void {
    if (self.render_target) |v| _ = v.Release();
    if (self.shader_view) |v| _ = v.Release();
    if (self.texture) |v| _ = v.Release();
}

pub fn replaceRegion(
    self: *Self,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    data: []const u8,
) Error!void {
    if (x >= self.width or y >= self.height) return;
    const copy_w = @min(width, self.width - x);
    const copy_h = @min(height, self.height - y);
    if (copy_w == 0 or copy_h == 0) return;

    const texture = self.texture orelse return error.D3D11Failed;
    const bpp = bytesPerPixel(self.format);
    if (bpp == 0) return;

    // Use UpdateSubresource for region updates
    // D3D11 allows updating .DEFAULT textures this way
    var box = d3d.BOX{
        .left = @intCast(x),
        .top = @intCast(y),
        .front = 0,
        .right = @intCast(x + copy_w),
        .bottom = @intCast(y + copy_h),
        .back = 1,
    };

    self.context.UpdateSubresource(
        @ptrCast(texture),
        0,
        &box,
        @constCast(data.ptr),
        @intCast(copy_w * bpp),
        0,
    );
}

pub fn bytesPerPixel(format: dxgi.FORMAT) usize {
    return switch (format) {
        .R8_UNORM => 1,
        .R8G8B8A8_UNORM,
        .R8G8B8A8_UNORM_SRGB,
        .B8G8R8A8_UNORM,
        .B8G8R8A8_UNORM_SRGB,
        => 4,
        else => 0,
    };
}
