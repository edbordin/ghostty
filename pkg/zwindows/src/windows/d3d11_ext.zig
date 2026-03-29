const windows = @import("../windows.zig");
const d3d = @import("d3dcommon.zig");
const d3d11 = @import("d3d11.zig");
const dxgi = @import("dxgi.zig");

pub fn D3D11CreateDevice(
    pAdapter: ?*dxgi.IAdapter,
    DriverType: d3d.DRIVER_TYPE,
    Software: ?windows.HINSTANCE,
    Flags: d3d11.CREATE_DEVICE_FLAG,
    pFeatureLevels: ?[*]const d3d.FEATURE_LEVEL,
    FeatureLevels: windows.UINT,
    SDKVersion: windows.UINT,
    ppDevice: ?*?*d3d11.IDevice,
    pFeatureLevel: ?*d3d.FEATURE_LEVEL,
    ppImmediateContext: ?*?*d3d11.IDeviceContext,
) windows.HRESULT {
    return d3d11.D3D11CreateDeviceAndSwapChain(
        pAdapter,
        DriverType,
        Software,
        Flags,
        pFeatureLevels,
        FeatureLevels,
        SDKVersion,
        null,
        null,
        ppDevice,
        pFeatureLevel,
        ppImmediateContext,
    );
}

pub fn DrawInstanced(
    context: *d3d11.IDeviceContext,
    vertex_count_per_instance: windows.UINT,
    instance_count: windows.UINT,
    start_vertex_location: windows.UINT,
    start_instance_location: windows.UINT,
) void {
    const Fn = *const fn (
        *d3d11.IDeviceContext,
        windows.UINT,
        windows.UINT,
        windows.UINT,
        windows.UINT,
    ) callconv(windows.WINAPI) void;
    const f: Fn = @ptrCast(@alignCast(context.__v.DrawInstanced));
    f(
        context,
        vertex_count_per_instance,
        instance_count,
        start_vertex_location,
        start_instance_location,
    );
}
