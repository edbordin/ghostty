const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = b.addModule("zwindows", .{
        .root_source_file = b.path("src/windows.zig"),
    });
}
