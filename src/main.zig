//! pgz CLI

const std = @import("std");

pub fn main() !void {
    const stdout = std.posix.STDOUT_FILENO;
    _ = try std.posix.write(stdout, "pgz — SSD-first storage engine (M0 in progress)\n");
    _ = try std.posix.write(stdout, "Run `zig build test` to run tests.\n");
}

test {
    _ = @import("root.zig");
}
