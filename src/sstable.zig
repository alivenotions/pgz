//! SSTable — Sorted String Table for on-disk key storage.
//!
//! Block format:
//! ┌──────────────┬───────────┬────────────────────┬───────────┬────────────┐
//! │ block_len: u32 │ count: u32 │ entries...       │ crc32c: u32 │ pad→4KiB │
//! └──────────────┴───────────┴────────────────────┴───────────┴────────────┘

const std = @import("std");
const types = @import("types.zig");

pub const Entry = struct {
    key: []const u8,
    vptr: types.ValuePointer,
    epoch: types.Epoch,
};

pub const Builder = struct {
    // TODO: implement
    pub fn init(allocator: std.mem.Allocator) Builder {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *Builder) void {
        _ = self;
    }
    pub fn add(self: *Builder, key: []const u8, vptr: types.ValuePointer, epoch: types.Epoch) !void {
        _ = self;
        _ = key;
        _ = vptr;
        _ = epoch;
    }
    pub fn finish(self: *Builder) !void {
        _ = self;
    }
};

pub const Reader = struct {
    // TODO: implement
    pub fn open(allocator: std.mem.Allocator, path: []const u8) !Reader {
        _ = allocator;
        _ = path;
        return .{};
    }
    pub fn deinit(self: *Reader) void {
        _ = self;
    }
    pub fn get(self: *Reader, key: []const u8) !?Entry {
        _ = self;
        _ = key;
        return null;
    }
};
