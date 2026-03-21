//! Compiles a blueprint file using `blueprint-compiler`. This performs
//! additional checks to ensure that various minimum versions are met.
//!
//! Usage: blueprint.zig <major> <minor> <output> <input>
//!
//! Example: blueprint.zig 1 5 output.ui input.blp

const std = @import("std");
const builtin = @import("builtin");

/// Write to the real stderr fd. `std.debug.print` can be disconnected from the handle Zig's build
/// runner pipes on Windows, which produced empty `error: stderr:` for failed blueprint steps.
fn logErr(comptime fmt: []const u8, args: anytype) void {
    const stderr_file = std.fs.File.stderr();
    stderr_file.deprecatedWriter().print(fmt, args) catch return;
    stderr_file.sync() catch return;
}

/// Child stdout/stderr capture limit (Python tracebacks exceed 64 KiB easily).
const blueprint_child_max_output: usize = 4 * 1024 * 1024;

pub const c = @cImport({
    @cInclude("adwaita.h");
});

pub const blueprint_compiler_help =
    \\
    \\When building from a Git checkout, Ghostty requires
    \\version {f} or newer of `blueprint-compiler` as a
    \\build-time dependency. Please install it, ensure that it
    \\is available on your PATH, and then retry building Ghostty.
    \\See `HACKING.md` for more details.
    \\
    \\This message should *not* appear for normal users, who
    \\should build Ghostty from official release tarballs instead.
    \\Please consult https://ghostty.org/docs/install/build for
    \\more information on the recommended build instructions.
;

const adwaita_version = std.SemanticVersion{
    .major = c.ADW_MAJOR_VERSION,
    .minor = c.ADW_MINOR_VERSION,
    .patch = c.ADW_MICRO_VERSION,
};
const required_blueprint_version = std.SemanticVersion{
    .major = 0,
    .minor = 16,
    .patch = 0,
};

/// How to spawn blueprint-compiler. MSYS2 installs Meson's `blueprint-compiler` as a Python script
/// (not a PE .exe); on Windows use `GHOSTTY_BLUEPRINT_PYTHON` + `GHOSTTY_BLUEPRINT_SCRIPT`, or a
/// single `GHOSTTY_BLUEPRINT_COMPILER` / `BLUEPRINT_COMPILER` if it is a real executable.
const BlueprintCmd = struct {
    exe: []const u8,
    /// argv slots between `exe` and blueprint-compiler's own flags (e.g. script path for Python).
    prefix: []const []const u8,

    fn deinit(self: *BlueprintCmd, a: std.mem.Allocator) void {
        a.free(self.exe);
        for (self.prefix) |s| a.free(s);
        a.free(self.prefix);
    }
};

fn resolveBlueprintCmd(alloc: std.mem.Allocator) error{OutOfMemory}!BlueprintCmd {
    if (std.process.getEnvVarOwned(alloc, "GHOSTTY_BLUEPRINT_PYTHON")) |py_raw| {
        defer alloc.free(py_raw);
        const py_t = std.mem.trim(u8, py_raw, " \t\r\n");
        if (py_t.len != 0) {
            if (std.process.getEnvVarOwned(alloc, "GHOSTTY_BLUEPRINT_SCRIPT")) |sc_raw| {
                defer alloc.free(sc_raw);
                const sc_t = std.mem.trim(u8, sc_raw, " \t\r\n");
                if (sc_t.len != 0) {
                    const prefix = try alloc.alloc([]const u8, 1);
                    errdefer alloc.free(prefix);
                    prefix[0] = try alloc.dupe(u8, sc_t);
                    errdefer alloc.free(prefix[0]);
                    return .{
                        .exe = try alloc.dupe(u8, py_t),
                        .prefix = prefix,
                    };
                }
            } else |_| {}
        }
    } else |_| {}

    inline for (&[_][]const u8{ "GHOSTTY_BLUEPRINT_COMPILER", "BLUEPRINT_COMPILER" }) |key| {
        if (std.process.getEnvVarOwned(alloc, key)) |p| {
            defer alloc.free(p);
            const t = std.mem.trim(u8, p, " \t\r\n");
            if (t.len != 0) {
                return .{
                    .exe = try alloc.dupe(u8, t),
                    .prefix = try alloc.alloc([]const u8, 0),
                };
            }
        } else |_| {}
    }

    if (builtin.os.tag == .windows) {
        return .{
            .exe = try alloc.dupe(u8, "blueprint-compiler.exe"),
            .prefix = try alloc.alloc([]const u8, 0),
        };
    }

    return .{
        .exe = try alloc.dupe(u8, "blueprint-compiler"),
        .prefix = try alloc.alloc([]const u8, 0),
    };
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    const alloc = debug_allocator.allocator();

    var bp_cmd = try resolveBlueprintCmd(alloc);
    defer bp_cmd.deinit(alloc);

    // Get our args
    var it = try std.process.argsWithAllocator(alloc);
    defer it.deinit();
    _ = it.next(); // Skip argv0
    const arg_major = it.next() orelse return error.NoMajorVersion;
    const arg_minor = it.next() orelse return error.NoMinorVersion;
    const output = it.next() orelse return error.NoOutput;
    const input = it.next() orelse return error.NoInput;

    const required_adwaita_version = std.SemanticVersion{
        .major = try std.fmt.parseUnsigned(u8, arg_major, 10),
        .minor = try std.fmt.parseUnsigned(u8, arg_minor, 10),
        .patch = 0,
    };
    if (adwaita_version.order(required_adwaita_version) == .lt) {
        logErr(
            \\`libadwaita` is too old.
            \\
            \\Ghostty requires a version {f} or newer of `libadwaita` to
            \\compile this blueprint. Please install it, ensure that it is
            \\available on your PATH, and then retry building Ghostty.
            \\
        , .{required_adwaita_version});
        std.process.exit(1);
    }

    // Version checks
    {
        var stdout: std.ArrayListUnmanaged(u8) = .empty;
        defer stdout.deinit(alloc);
        var stderr: std.ArrayListUnmanaged(u8) = .empty;
        defer stderr.deinit(alloc);

        const argv = try alloc.alloc([]const u8, 2 + bp_cmd.prefix.len);
        defer alloc.free(argv);
        argv[0] = bp_cmd.exe;
        @memcpy(argv[1 .. 1 + bp_cmd.prefix.len], bp_cmd.prefix);
        argv[1 + bp_cmd.prefix.len] = "--version";

        var blueprint_compiler = std.process.Child.init(argv, alloc);
        blueprint_compiler.stdout_behavior = .Pipe;
        blueprint_compiler.stderr_behavior = .Pipe;
        try spawnBlueprintCompiler(&blueprint_compiler);
        try blueprint_compiler.collectOutput(
            alloc,
            &stdout,
            &stderr,
            blueprint_child_max_output,
        );
        const term = blueprint_compiler.wait() catch |err| switch (err) {
            error.FileNotFound => {
                logErr(
                    \\`blueprint-compiler` not found.
                ++ blueprint_compiler_help,
                    .{required_blueprint_version},
                );
                std.process.exit(1);
            },
            else => return err,
        };
        switch (term) {
            .Exited => |rc| {
                if (rc != 0) {
                    logErr(
                        "blueprint-compiler --version exited with code {d}.\nstdout:\n{s}\nstderr:\n{s}\n",
                        .{ rc, stdout.items, stderr.items },
                    );
                    std.process.exit(1);
                }
            },
            else => {
                logErr(
                    "blueprint-compiler --version did not exit normally.\nstdout:\n{s}\nstderr:\n{s}\n",
                    .{ stdout.items, stderr.items },
                );
                std.process.exit(1);
            },
        }

        const trimmed = std.mem.trim(u8, stdout.items, &std.ascii.whitespace);
        const version = std.SemanticVersion.parse(trimmed) catch {
            logErr(
                "could not parse blueprint-compiler version from stdout (expected semver).\nstdout:\n{s}\nstderr:\n{s}\n",
                .{ stdout.items, stderr.items },
            );
            std.process.exit(1);
        };
        if (version.order(required_blueprint_version) == .lt) {
            logErr(
                \\`blueprint-compiler` is the wrong version.
            ++ blueprint_compiler_help,
                .{required_blueprint_version},
            );
            std.process.exit(1);
        }
    }

    // Compilation
    {
        var stdout: std.ArrayListUnmanaged(u8) = .empty;
        defer stdout.deinit(alloc);
        var stderr: std.ArrayListUnmanaged(u8) = .empty;
        defer stderr.deinit(alloc);

        const argv = try alloc.alloc([]const u8, 5 + bp_cmd.prefix.len);
        defer alloc.free(argv);
        argv[0] = bp_cmd.exe;
        @memcpy(argv[1 .. 1 + bp_cmd.prefix.len], bp_cmd.prefix);
        const j = 1 + bp_cmd.prefix.len;
        argv[j + 0] = "compile";
        argv[j + 1] = "--output";
        argv[j + 2] = output;
        argv[j + 3] = input;

        var blueprint_compiler = std.process.Child.init(argv, alloc);
        blueprint_compiler.stdout_behavior = .Pipe;
        blueprint_compiler.stderr_behavior = .Pipe;
        try spawnBlueprintCompiler(&blueprint_compiler);
        try blueprint_compiler.collectOutput(
            alloc,
            &stdout,
            &stderr,
            blueprint_child_max_output,
        );
        const term = blueprint_compiler.wait() catch |err| switch (err) {
            error.FileNotFound => {
                logErr(
                    \\`blueprint-compiler` not found.
                ++ blueprint_compiler_help,
                    .{required_blueprint_version},
                );
                std.process.exit(1);
            },
            else => return err,
        };

        switch (term) {
            .Exited => |rc| {
                if (rc != 0) {
                    if (stderr.items.len != 0) {
                        logErr("{s}", .{stderr.items});
                    } else if (stdout.items.len != 0) {
                        logErr("{s}", .{stdout.items});
                    } else {
                        logErr(
                            "blueprint-compiler compile exited with code {d} (no stdout/stderr).\n",
                            .{rc},
                        );
                    }
                    std.process.exit(1);
                }
            },
            else => {
                logErr("stderr:\n{s}\nstdout:\n{s}\n", .{ stderr.items, stdout.items });
                std.process.exit(1);
            },
        }
    }
}

fn spawnBlueprintCompiler(child: *std.process.Child) !void {
    child.spawn() catch |err| {
        switch (err) {
            error.FileNotFound => {
                logErr(
                    \\`blueprint-compiler` not found.
                ++ blueprint_compiler_help,
                    .{required_blueprint_version},
                );
                std.process.exit(1);
            },
            else => {
                if (builtin.os.tag == .windows and err == error.InvalidExe) {
                    logErr(
                        \\Could not run blueprint-compiler (not a valid Windows executable). MSYS2 installs
                        \\it as a Python script: use GHOSTTY_BLUEPRINT_PYTHON + GHOSTTY_BLUEPRINT_SCRIPT
                        \\(see the Ghostty MinGW build script).
                        \\
                    , .{});
                    std.process.exit(1);
                }
                return err;
            },
        }
    };
}
