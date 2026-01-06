//! LSM Tree — Log-Structured Merge Tree.
//!
//! Manages MemTable + on-disk levels with compaction.

const std = @import("std");
const types = @import("types.zig");

pub const MemEntry = struct {
    vptr: types.ValuePointer,
    epoch: types.Epoch,
    is_tombstone: bool,
};

pub const MemTable = struct {
    size_bytes: usize = 0,
    pub const DefaultMaxSize: usize = 64 * 1024 * 1024;

    pub fn init(allocator: std.mem.Allocator) MemTable {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *MemTable) void {
        _ = self;
    }
    pub fn put(self: *MemTable, key: []const u8, vptr: types.ValuePointer, epoch: types.Epoch) !void {
        _ = self;
        _ = key;
        _ = vptr;
        _ = epoch;
    }
    pub fn delete(self: *MemTable, key: []const u8, epoch: types.Epoch) !void {
        _ = self;
        _ = key;
        _ = epoch;
    }
    pub fn get(self: *MemTable, key: []const u8) ?MemEntry {
        _ = self;
        _ = key;
        return null;
    }
};

pub const Tree = struct {
    active_memtable: MemTable = .{},

    pub fn init(allocator: std.mem.Allocator) Tree {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *Tree) void {
        _ = self;
    }
    pub fn put(self: *Tree, key: []const u8, vptr: types.ValuePointer, epoch: types.Epoch) !void {
        _ = self;
        _ = key;
        _ = vptr;
        _ = epoch;
    }
    pub fn delete(self: *Tree, key: []const u8, epoch: types.Epoch) !void {
        _ = self;
        _ = key;
        _ = epoch;
    }
    pub fn get(self: *Tree, key: []const u8) !?MemEntry {
        _ = self;
        _ = key;
        return null;
    }
};
