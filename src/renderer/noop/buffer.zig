const std = @import("std");
const Noop = @import("../Noop.zig");

/// Trivial stand-in for an API buffer handle.
pub const Handle = struct {
    size: usize = 0,
};

/// Options for initializing a noop buffer.
pub const Options = struct {
    target: Noop.BufferTarget = .array,
    usage: Noop.BufferUsage = .dynamic_draw,
};

/// Noop data storage for equal types.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: Handle,
        opts: Options,
        len: usize,

        pub fn init(opts: Options, len: usize) !Self {
            return .{
                .buffer = .{ .size = len },
                .opts = opts,
                .len = len,
            };
        }

        pub fn initFill(opts: Options, data: []const T) !Self {
            return .{
                .buffer = .{ .size = data.len },
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
        }

        pub fn syncFromArrayLists(
            self: *Self,
            lists: []const std.ArrayListUnmanaged(T),
        ) !usize {
            var total_len: usize = 0;
            for (lists) |list| total_len += list.items.len;
            if (total_len > self.len) self.len = total_len;
            self.buffer.size = self.len;
            return total_len;
        }
    };
}
