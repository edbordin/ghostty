//! D3D11 API types used by the renderer abstraction layer.
const zw = @import("zwindows");
const d3d = zw.d3d;

/// Primitive topology type. Names match Metal's MTLPrimitiveType for generic.zig compatibility.
pub const Primitive = enum(u32) {
    point = @intFromEnum(d3d.PRIMITIVE_TOPOLOGY.POINTLIST),
    line = @intFromEnum(d3d.PRIMITIVE_TOPOLOGY.LINELIST),
    line_strip = @intFromEnum(d3d.PRIMITIVE_TOPOLOGY.LINESTRIP),
    triangle = @intFromEnum(d3d.PRIMITIVE_TOPOLOGY.TRIANGLELIST),
    triangle_strip = @intFromEnum(d3d.PRIMITIVE_TOPOLOGY.TRIANGLESTRIP),

    pub fn toD3D(self: Primitive) d3d.PRIMITIVE_TOPOLOGY {
        return @enumFromInt(@intFromEnum(self));
    }
};
