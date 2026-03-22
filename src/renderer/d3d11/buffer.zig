const std = @import("std");
const D3D11 = @import("../D3D11.zig");

/// Trivial stand-in for an API buffer handle.
pub const Handle = struct {
    size: usize = 0,
    bg_color: ?[4]u8 = null,
};

/// Options for initializing a noop buffer.
pub const Options = struct {
    target: D3D11.BufferTarget = .array,
    usage: D3D11.BufferUsage = .dynamic_draw,
};

/// D3D11 data storage for equal types.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: Handle,
        opts: Options,
        len: usize,

        pub fn init(opts: Options, len: usize) !Self {
            return .{
                .buffer = .{
                    .size = len,
                    .bg_color = null,
                },
                .opts = opts,
                .len = len,
            };
        }

        pub fn initFill(opts: Options, data: []const T) !Self {
            var buf: Handle = .{
                .size = data.len,
                .bg_color = null,
            };
            assignBgColor(T, &buf, data);
            return .{
                .buffer = buf,
                .opts = opts,
                .len = data.len,
            };
        }

        pub fn deinit(self: Self) void {
            _ = self;
        }

        pub fn sync(self: *Self, data: []const T) !void {
            if (data.len > self.len) self.len = data.len;
            self.buffer.size = self.len;
            assignBgColor(T, &self.buffer, data);
        }

        pub fn syncFromArrayLists(
            self: *Self,
            lists: []const std.ArrayListUnmanaged(T),
        ) !usize {
            var total_len: usize = 0;
            for (lists) |list| total_len += list.items.len;
            if (total_len > self.len) self.len = total_len;
            self.buffer.size = self.len;
            self.buffer.bg_color = null;
            return total_len;
        }

        fn assignBgColor(comptime Elem: type, handle: *Handle, data: []const Elem) void {
            if (data.len == 0) {
                handle.bg_color = null;
                return;
            }

            if (!@hasField(Elem, "bg_color")) {
                handle.bg_color = null;
                return;
            }

            const bg = @field(data[0], "bg_color");
            if (@TypeOf(bg) == [4]u8) {
                handle.bg_color = bg;
                return;
            }

            handle.bg_color = null;
        }
    };
}
