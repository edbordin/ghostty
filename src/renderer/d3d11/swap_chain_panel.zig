const builtin = @import("builtin");

const win32 = if (builtin.os.tag == .windows) @import("win32").everything else struct {};

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

pub fn setSwapChain(
    swap_chain_panel: *anyopaque,
    swap_chain: *win32.IDXGISwapChain1,
) bool {
    if (builtin.os.tag != .windows) return false;
    const panel_native: *ISwapChainPanelNative = @ptrCast(@alignCast(swap_chain_panel));
    const swap_chain_base: *win32.IDXGISwapChain = @ptrCast(swap_chain);
    const hr = panel_native.SetSwapChain(swap_chain_base);
    return hr >= 0;
}
