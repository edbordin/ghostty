pub fn releaseAndNull(comptime Interface: type, ptr: *?*Interface) void {
    if (ptr.*) |v| {
        _ = v.Release();
        ptr.* = null;
    }
}
