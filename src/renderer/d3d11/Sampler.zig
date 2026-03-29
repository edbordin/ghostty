//! Wrapper for D3D11 sampler state.
const Self = @This();

const Texture = @import("Texture.zig");
const std = @import("std");
const d3d = @import("zwindows").d3d11;
const win32ext = @import("win32ext.zig");

pub const Options = struct {
    device: *d3d.IDevice,
    filter: d3d.FILTER,
    address_u: d3d.TEXTURE_ADDRESS_MODE,
    address_v: d3d.TEXTURE_ADDRESS_MODE,
};

pub const Error = error{D3D11Failed};

opts: Options,
state: ?*d3d.ISamplerState = null,

pub fn init(opts: Options) Error!Self {
    var desc: d3d.SAMPLER_DESC = .{
        .Filter = opts.filter,
        .AddressU = opts.address_u,
        .AddressV = opts.address_v,
        .AddressW = d3d.TEXTURE_ADDRESS_MODE.CLAMP,
        .MipLODBias = 0.0,
        .MaxAnisotropy = 1,
        .ComparisonFunc = d3d.COMPARISON_FUNC.NEVER,
        .BorderColor = .{ 0.0, 0.0, 0.0, 0.0 },
        .MinLOD = 0.0,
        .MaxLOD = 0.0, // clamp to avoid any mipmapping
    };

    var sampler: ?*d3d.ISamplerState = null;
    const hr = opts.device.CreateSamplerState(&desc, @ptrCast(&sampler));
    if (hr < 0 or sampler == null) return error.D3D11Failed;

    return .{
        .opts = opts,
        .state = sampler,
    };
}

pub fn deinit(self: *Self) void {
    win32ext.releaseAndNull(d3d.ISamplerState, &self.state);
}
