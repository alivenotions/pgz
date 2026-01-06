//! Platform-agnostic I/O abstraction layer.
//!
//! Provides unified interface for:
//! - macOS: kqueue + F_NOCACHE + F_FULLFSYNC
//! - Linux: io_uring + O_DIRECT (future)

const std = @import("std");
const types = @import("types.zig");

pub const PageSize = types.PageSize;

// =============================================================================
// I/O Operation Types
// =============================================================================

pub const OpType = enum { read, write, fsync };

pub const IOOp = struct {
    op_type: OpType,
    fd: std.posix.fd_t,
    buffer: ?[]u8 = null,
    offset: u64 = 0,
    userdata: usize = 0,
};

pub const Completion = struct {
    op: IOOp,
    result: union(enum) { success: usize, err: anyerror },
};

// =============================================================================
// File Handle
// =============================================================================

pub const OpenOptions = struct {
    create: bool = false,
    truncate: bool = false,
    read: bool = true,
    write: bool = false,
    direct: bool = true,
};

pub const FileHandle = struct {
    fd: std.posix.fd_t,

    pub fn close(self: *FileHandle) void {
        std.posix.close(self.fd);
    }

    pub fn getSize(self: FileHandle) !u64 {
        const stat = try std.posix.fstat(self.fd);
        return @intCast(stat.size);
    }
};

// =============================================================================
// Platform Functions (to be implemented)
// =============================================================================

pub fn openFile(path: []const u8, options: OpenOptions) !FileHandle {
    _ = path;
    _ = options;
    @panic("TODO: implement openFile");
}

pub fn performSync(fd: std.posix.fd_t) !void {
    _ = fd;
    @panic("TODO: implement performSync");
}

pub fn allocAligned(allocator: std.mem.Allocator, len: usize) ![]align(PageSize) u8 {
    _ = allocator;
    _ = len;
    @panic("TODO: implement allocAligned");
}

pub fn freeAligned(allocator: std.mem.Allocator, buf: []align(PageSize) u8) void {
    _ = allocator;
    _ = buf;
    @panic("TODO: implement freeAligned");
}
