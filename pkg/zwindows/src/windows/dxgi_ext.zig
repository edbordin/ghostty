const windows = @import("../windows.zig");
const dxgi = @import("dxgi.zig");

pub fn CreateSwapChainForComposition(
    factory: *dxgi.IFactory2,
    device: *windows.IUnknown,
    desc: *const dxgi.SWAP_CHAIN_DESC1,
    restrict_to_output: ?*dxgi.IOutput,
    swap_chain: *?*dxgi.ISwapChain1,
) windows.HRESULT {
    const Fn = *const fn (
        *dxgi.IFactory2,
        *windows.IUnknown,
        *const dxgi.SWAP_CHAIN_DESC1,
        ?*dxgi.IOutput,
        *?*dxgi.ISwapChain1,
    ) callconv(windows.WINAPI) windows.HRESULT;
    const f: Fn = @ptrCast(@alignCast(factory.__v.CreateSwapChainForComposition));
    return f(factory, device, desc, restrict_to_output, swap_chain);
}
