const std = @import("std");
const D3D11 = @import("../D3D11.zig");

/// Trivial stand-in for an API buffer handle.
pub const Handle = struct {
    size: usize = 0,
    len: usize = 0,
    stride: usize = 0,
    bytes: []const u8 = &.{},
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
        cap: usize,
        data: []T,

        pub fn init(opts: Options, len: usize) !Self {
            const safe_len = if (len > 0) len else 1;
            const buf = try std.heap.page_allocator.alloc(T, safe_len);
            return .{
                .buffer = .{
                    .size = safe_len,
                    .len = 0,
                    .stride = @sizeOf(T),
                    .bytes = &.{},
                    .bg_color = null,
                },
                .opts = opts,
                .cap = safe_len,
                .data = buf,
            };
        }

        pub fn initFill(opts: Options, data: []const T) !Self {
            var self = try init(opts, if (data.len > 0) data.len else 1);
            try self.sync(data);
            return self;
        }

        pub fn deinit(self: Self) void {
            std.heap.page_allocator.free(self.data);
        }

        pub fn sync(self: *Self, data: []const T) !void {
            try self.ensureCapacity(data.len);
            if (data.len > 0) {
                @memcpy(self.data[0..data.len], data);
            }

            self.buffer.size = self.cap;
            self.buffer.len = data.len;
            self.buffer.stride = @sizeOf(T);
            self.buffer.bytes = std.mem.sliceAsBytes(self.data[0..data.len]);
            assignBgColor(T, &self.buffer, data);
        }

        pub fn syncFromArrayLists(
            self: *Self,
            lists: []const std.ArrayListUnmanaged(T),
        ) !usize {
            var total_len: usize = 0;
            for (lists) |list| total_len += list.items.len;

            try self.ensureCapacity(total_len);

            var offset: usize = 0;
            for (lists) |list| {
                if (list.items.len == 0) continue;
                @memcpy(self.data[offset .. offset + list.items.len], list.items);
                offset += list.items.len;
            }

            self.buffer.size = self.cap;
            self.buffer.len = total_len;
            self.buffer.stride = @sizeOf(T);
            self.buffer.bytes = std.mem.sliceAsBytes(self.data[0..total_len]);
            if (total_len > 0) {
                assignBgColor(T, &self.buffer, self.data[0..total_len]);
            } else {
                self.buffer.bg_color = null;
            }
            return total_len;
        }

        fn ensureCapacity(self: *Self, needed: usize) !void {
            if (needed <= self.cap) return;

            const grown = @max(self.cap * 2, needed);
            const new_data = try std.heap.page_allocator.alloc(T, grown);
            if (self.buffer.len > 0) {
                @memcpy(new_data[0..self.buffer.len], self.data[0..self.buffer.len]);
            }
            std.heap.page_allocator.free(self.data);
            self.data = new_data;
            self.cap = grown;
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
