//! Value Log — Append-only storage for row values.
//!
//! Record format:
//! ┌──────────┬───────────┬─────────────────┬────────────────────┐
//! │ len: u32 │ crc32c: u32 │ payload: bytes │ zero-pad → 4KiB  │
//! └──────────┴───────────┴─────────────────┴────────────────────┘

const std = @import("std");
const types = @import("types.zig");

pub const RecordHeaderSize: usize = 8;

pub const Writer = struct {
    // TODO: implement
    pub fn init(allocator: std.mem.Allocator, segment_id: types.SegmentId) Writer {
        _ = allocator;
        _ = segment_id;
        return .{};
    }
    pub fn deinit(self: *Writer) void {
        _ = self;
    }
    pub fn append(self: *Writer, payload: []const u8) !types.ValuePointer {
        _ = self;
        _ = payload;
        @panic("TODO: implement");
    }
    pub fn sync(self: *Writer) !void {
        _ = self;
    }
};

pub const Reader = struct {
    // TODO: implement
    pub fn init(allocator: std.mem.Allocator) Reader {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *Reader) void {
        _ = self;
    }
    pub fn read(self: *Reader, vptr: types.ValuePointer, buf: []u8) ![]const u8 {
        _ = self;
        _ = vptr;
        _ = buf;
        @panic("TODO: implement");
    }
};

pub fn scanLastGood(allocator: std.mem.Allocator, path: []const u8) !types.Offset {
    _ = allocator;
    _ = path;
    @panic("TODO: implement");
}
