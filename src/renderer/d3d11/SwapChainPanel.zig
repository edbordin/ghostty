const Self = @This();

const zw = @import("zwindows");
const dxgi = zw.dxgi;

panel: *anyopaque,

const ISwapChainPanelNative = extern union {
    pub const VTable = extern struct {
        base: zw.IUnknown.VTable,
        SetSwapChain: *const fn (
            self: *const ISwapChainPanelNative,
            swap_chain: ?*dxgi.ISwapChain,
        ) callconv(.winapi) zw.HRESULT,
    };

    vtable: *const VTable,
    IUnknown: zw.IUnknown,

    pub inline fn SetSwapChain(
        self: *const ISwapChainPanelNative,
        swap_chain: ?*dxgi.ISwapChain,
    ) zw.HRESULT {
        return self.vtable.SetSwapChain(self, swap_chain);
    }
};

pub fn setSwapChain(
    self: *const Self,
    swap_chain: *dxgi.ISwapChain1,
) bool {
    const panel_native: *ISwapChainPanelNative = @ptrCast(@alignCast(self.panel));
    const swap_chain_base: *dxgi.ISwapChain = @ptrCast(swap_chain);
    const hr = panel_native.SetSwapChain(swap_chain_base);
    return hr >= 0;
}

pub fn init(panel: *anyopaque) Self {
    return .{ .panel = panel };
}
