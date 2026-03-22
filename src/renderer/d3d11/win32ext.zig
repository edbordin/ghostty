const std = @import("std");
const win32 = @import("win32").everything;

pub fn queryInterface(obj: anytype, comptime Interface: type) *Interface {
    const obj_name_start: usize = comptime if (std.mem.lastIndexOfScalar(u8, @typeName(@TypeOf(obj)), '.')) |i| (i + 1) else 0;
    const obj_name = @typeName(@TypeOf(obj))[obj_name_start..];
    const iface_name_start: usize = comptime if (std.mem.lastIndexOfScalar(u8, @typeName(Interface), '.')) |i| (i + 1) else 0;
    const iface_name = @typeName(Interface)[iface_name_start..];

    const iid_name = "IID_" ++ iface_name;
    const iid = @field(win32, iid_name);

    var iface: *Interface = undefined;
    const hr = obj.IUnknown.QueryInterface(iid, @ptrCast(&iface));
    if (hr < 0) std.debug.panic(
        "QueryInterface on " ++ obj_name ++ " as " ++ iface_name ++ " failed, hresult=0x{x}",
        .{@as(u32, @bitCast(hr))},
    );

    return iface;
}

pub fn releaseAndNull(comptime Interface: type, ptr: *?*Interface) void {
    if (ptr.*) |v| {
        _ = v.IUnknown.Release();
        ptr.* = null;
    }
}
