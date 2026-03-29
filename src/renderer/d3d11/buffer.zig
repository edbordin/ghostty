const std = @import("std");
const D3D11 = @import("../D3D11.zig");
const zw = @import("zwindows");
const d3d = zw.d3d11;
const dxgi = zw.dxgi;
const win32ext = @import("win32ext.zig");

/// Usage pattern for a buffer, matching D3D11's memory model.
/// These map to D3D11_USAGE with semantics similar to Metal's storage modes
/// and OpenGL's usage hints.
pub const Usage = enum {
    /// GPU read-only, set once at creation. Cannot be updated after creation.
    /// Equivalent to Metal .private with initial data, OpenGL .static_draw.
    /// Maps to D3D11_IMMUTABLE.
    immutable,

    /// GPU read-only, updated occasionally (e.g., font atlas).
    /// Updated via UpdateSubresource (driver handles staging).
    /// Equivalent to Metal .private with replaceRegion, OpenGL .dynamic_draw.
    /// Maps to D3D11_DEFAULT with no CPU access.
    default,

    /// CPU write, GPU read, updated frequently per-frame.
    /// Updated via Map(WRITE_DISCARD) for efficient ring-buffering.
    /// Equivalent to Metal .shared/.managed with contents, OpenGL .dynamic_draw.
    /// Maps to D3D11_DYNAMIC with CPU_ACCESS_WRITE.
    dynamic,

    /// CPU read/write, used for staging data to/from GPU.
    /// Used for texture updates or readback.
    /// Maps to D3D11_STAGING with CPU_ACCESS_READ|WRITE.
    staging,
};

/// Native buffer handle shared with render passes
pub const Handle = struct {
    len: usize = 0,
    stride: usize = 0,
    native: ?*d3d.IBuffer = null,
    shader_view: ?*d3d.IShaderResourceView = null,
};

/// Options for initializing a D3D11 buffer.
pub const Options = struct {
    device: *d3d.IDevice,
    context: *d3d.IDeviceContext,
    target: D3D11.BufferTarget = .array,
    shader_resource_format: ?dxgi.FORMAT = null,
    usage: Usage = .dynamic,
};

/// D3D11 data storage for equal types.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: Handle,
        opts: Options,

        pub fn init(opts: Options, len: usize) !Self {
            const safe_len = if (len > 0) len else 1;
            const resources = try createNativeResources(opts.device, safe_len, @sizeOf(T), opts);
            return .{
                .buffer = .{
                    .len = safe_len,
                    .stride = @sizeOf(T),
                    .native = resources.buffer,
                    .shader_view = resources.shader_view,
                },
                .opts = opts,
            };
        }

        pub fn initFill(opts: Options, data: []const T) !Self {
            const safe_len = if (data.len > 0) data.len else 1;

            // For immutable buffers, data must be provided at creation time
            if (opts.usage == .immutable and data.len == 0) {
                return error.ImmutableBufferRequiresData;
            }

            const resources = try createNativeResources(opts.device, safe_len, @sizeOf(T), opts);
            var self = Self{
                .buffer = .{
                    .len = safe_len,
                    .stride = @sizeOf(T),
                    .native = resources.buffer,
                    .shader_view = resources.shader_view,
                },
                .opts = opts,
            };

            // sync() will handle uploading data appropriately for each usage type
            try self.sync(data);
            return self;
        }

        pub fn deinit(self: *Self) void {
            win32ext.releaseAndNull(d3d.IBuffer, &self.buffer.native);
            win32ext.releaseAndNull(d3d.IShaderResourceView, &self.buffer.shader_view);
        }

        pub fn sync(self: *Self, data: []const T) !void {
            const data_len = if (data.len > 0) data.len else 1;
            try self.ensureCapacity(data_len);
            self.buffer.stride = @sizeOf(T);

            if (data.len > 0) {
                const native = self.buffer.native orelse return;
                const src = std.mem.sliceAsBytes(data);

                switch (self.opts.usage) {
                    .dynamic => {
                        // Use Map(WRITE_DISCARD) for per-frame updates
                        const resource: *d3d.IResource = @ptrCast(native);
                        var mapped: d3d.MAPPED_SUBRESOURCE = undefined;
                        const map_hr = self.opts.context.Map(resource, 0, d3d.MAP.WRITE_DISCARD, .{}, &mapped);
                        if (map_hr < 0) return error.D3D11Failed;
                        defer self.opts.context.Unmap(resource, 0);

                        const dst: [*]u8 = @ptrCast(mapped.pData);
                        @memcpy(dst[0..src.len], src);
                    },
                    .default => {
                        // Use UpdateSubresource for occasional updates
                        self.opts.context.UpdateSubresource(
                            @ptrCast(native),
                            0,
                            null,
                            @constCast(src.ptr),
                            @intCast(src.len),
                            0,
                        );
                    },
                    .immutable => {
                        // Immutable buffers cannot be updated after creation
                        return error.ImmutableBuffer;
                    },
                    .staging => {
                        // Staging buffers are mapped for CPU access
                        const resource: *d3d.IResource = @ptrCast(native);
                        var mapped: d3d.MAPPED_SUBRESOURCE = undefined;
                        const map_hr = self.opts.context.Map(resource, 0, d3d.MAP.WRITE, .{}, &mapped);
                        if (map_hr < 0) return error.D3D11Failed;
                        defer self.opts.context.Unmap(resource, 0);

                        const dst: [*]u8 = @ptrCast(mapped.pData);
                        @memcpy(dst[0..src.len], src);
                    },
                }
            }
        }

        pub fn syncFromArrayLists(
            self: *Self,
            lists: []const std.ArrayListUnmanaged(T),
        ) !usize {
            var total_len: usize = 0;
            for (lists) |list| total_len += list.items.len;
            const data_len = if (total_len > 0) total_len else 1;
            try self.ensureCapacity(data_len);
            self.buffer.stride = @sizeOf(T);

            if (total_len > 0) {
                const native = self.buffer.native orelse return error.D3D11Failed;

                switch (self.opts.usage) {
                    .dynamic => {
                        const resource: *d3d.IResource = @ptrCast(native);
                        var mapped: d3d.MAPPED_SUBRESOURCE = undefined;
                        const map_hr = self.opts.context.Map(resource, 0, d3d.MAP.WRITE_DISCARD, .{}, &mapped);
                        if (map_hr < 0) return error.D3D11Failed;
                        defer self.opts.context.Unmap(resource, 0);

                        const dst: [*]u8 = @ptrCast(mapped.pData);
                        var offset: usize = 0;

                        for (lists) |list| {
                            if (list.items.len == 0) continue;
                            const list_bytes = std.mem.sliceAsBytes(list.items);
                            @memcpy(dst[offset..][0..list_bytes.len], list_bytes);
                            offset += list_bytes.len;
                        }
                    },
                    .default => {
                        // Collect all data into a contiguous buffer for UpdateSubresource
                        const total_bytes = total_len * @sizeOf(T);
                        var staging = try std.heap.page_allocator.alloc(u8, total_bytes);
                        defer std.heap.page_allocator.free(staging);

                        var offset: usize = 0;
                        for (lists) |list| {
                            if (list.items.len == 0) continue;
                            const list_bytes = std.mem.sliceAsBytes(list.items);
                            @memcpy(staging[offset..][0..list_bytes.len], list_bytes);
                            offset += list_bytes.len;
                        }

                        self.opts.context.UpdateSubresource(
                            @ptrCast(native),
                            0,
                            null,
                            @constCast(staging.ptr),
                            @intCast(total_bytes),
                            0,
                        );
                    },
                    .immutable => return error.ImmutableBuffer,
                    .staging => {
                        const resource: *d3d.IResource = @ptrCast(native);
                        var mapped: d3d.MAPPED_SUBRESOURCE = undefined;
                        const map_hr = self.opts.context.Map(resource, 0, d3d.MAP.WRITE, .{}, &mapped);
                        if (map_hr < 0) return error.D3D11Failed;
                        defer self.opts.context.Unmap(resource, 0);

                        const dst: [*]u8 = @ptrCast(mapped.pData);
                        var offset: usize = 0;

                        for (lists) |list| {
                            if (list.items.len == 0) continue;
                            const list_bytes = std.mem.sliceAsBytes(list.items);
                            @memcpy(dst[offset..][0..list_bytes.len], list_bytes);
                            offset += list_bytes.len;
                        }
                    },
                }
            }

            return total_len;
        }

        fn ensureCapacity(self: *Self, needed: usize) !void {
            if (needed <= self.buffer.len) return;

            const grown = @max(self.buffer.len * 2, needed);

            const old_native = self.buffer.native;
            const old_shader_view = self.buffer.shader_view;

            const resources = try createNativeResources(self.opts.device, grown, @sizeOf(T), self.opts);
            self.buffer.native = resources.buffer;
            self.buffer.shader_view = resources.shader_view;
            self.buffer.len = grown;

            if (old_native != null) _ = old_native.?.Release();
            if (old_shader_view != null) _ = old_shader_view.?.Release();
        }
    };
}

const NativeResources = struct {
    buffer: ?*d3d.IBuffer = null,
    shader_view: ?*d3d.IShaderResourceView = null,
};

fn createNativeResources(
    device: *d3d.IDevice,
    len: usize,
    elem_size: usize,
    opts: Options,
) !NativeResources {
    const byte_width_unaligned = @max(@as(usize, 1), len * elem_size);
    const byte_width: u32 = switch (opts.target) {
        .uniform => @intCast((byte_width_unaligned + 15) & ~@as(usize, 15)),
        else => @intCast(byte_width_unaligned),
    };

    // Map our Usage enum to D3D11 flags
    const d3d_usage: d3d.USAGE = switch (opts.usage) {
        .immutable => .IMMUTABLE,
        .default => .DEFAULT,
        .dynamic => .DYNAMIC,
        .staging => .STAGING,
    };

    const cpu_access: d3d.CPU_ACCCESS_FLAG = switch (opts.usage) {
        .immutable => .{},
        .default => .{},
        .dynamic => .{ .WRITE = true },
        .staging => .{ .READ = true, .WRITE = true },
    };

    var bind_flags: d3d.BIND_FLAG = .{};
    switch (opts.target) {
        .array => bind_flags.VERTEX_BUFFER = true,
        .uniform => bind_flags.CONSTANT_BUFFER = true,
    }
    if (opts.shader_resource_format != null) {
        bind_flags.SHADER_RESOURCE = true;
    }

    const desc: d3d.BUFFER_DESC = .{
        .ByteWidth = byte_width,
        .Usage = d3d_usage,
        .BindFlags = bind_flags,
        .CPUAccessFlags = cpu_access,
        .MiscFlags = .{},
        .StructureByteStride = 0,
    };

    var native: ?*d3d.IBuffer = null;
    const hr = device.CreateBuffer(&desc, null, @ptrCast(&native));
    if (hr < 0 or native == null) return error.D3D11Failed;
    errdefer {
        var to_release = native;
        win32ext.releaseAndNull(d3d.IBuffer, &to_release);
    }

    var shader_view: ?*d3d.IShaderResourceView = null;
    if (opts.shader_resource_format) |format| {
        const num_elements: u32 = @intCast(@max(@as(usize, 1), len));
        const view_desc: d3d.SHADER_RESOURCE_VIEW_DESC = .{
            .Format = format,
            .ViewDimension = .BUFFER,
            .u = .{
                .Buffer = .{
                    .FirstElement = 0,
                    .NumElements = num_elements,
                },
            },
        };
        const view_hr = device.CreateShaderResourceView(
            @ptrCast(native.?),
            &view_desc,
            @ptrCast(&shader_view),
        );
        if (view_hr < 0 or shader_view == null) return error.D3D11Failed;
    }

    return .{
        .buffer = native,
        .shader_view = shader_view,
    };
}
