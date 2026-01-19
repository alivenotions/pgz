//! Test utilities for pgz.
//!
//! Provides:
//! - Temporary directory management
//! - Test assertions
//! - Fault injection hooks (future)

const std = @import("std");
const types = @import("types.zig");

/// Create a temporary directory for tests
pub fn tmpDir(allocator: std.mem.Allocator) !TmpDir {
    const path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(path);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&buf, "/tmp/pgz-test-{d}", .{std.time.milliTimestamp()});

    try std.fs.makeDirAbsolute(tmp_path);

    return .{
        .path = try allocator.dupe(u8, tmp_path),
        .allocator = allocator,
    };
}

pub const TmpDir = struct {
    path: []const u8,
    allocator: std.mem.Allocator,

    pub fn cleanup(self: *TmpDir) void {
        std.fs.deleteTreeAbsolute(self.path) catch {};
        self.allocator.free(self.path);
    }

    pub fn join(self: TmpDir, sub: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.path, sub });
    }
};

/// Assert that a buffer is page-aligned
pub fn assertAligned(buf: []const u8) !void {
    if (!types.isAligned(@intFromPtr(buf.ptr), types.PageSize)) {
        return error.UnalignedBuffer;
    }
    if (!types.isAligned(buf.len, types.PageSize)) {
        return error.UnalignedLength;
    }
}

test "TmpDir" {
    var dir = try tmpDir(std.testing.allocator);
    defer dir.cleanup();

    try std.testing.expect(std.fs.accessAbsolute(dir.path, .{}) != error.FileNotFound);
}
