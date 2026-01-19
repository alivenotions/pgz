//! Manifest — Database metadata and crash-safe state.
//!
//! Uses dual superblocks for atomic updates.

const std = @import("std");
const types = @import("types.zig");

pub const SuperblockMagic: u32 = 0x50475A53; // "PGZS"

pub const Superblock = struct {
    magic: u32 = SuperblockMagic,
    version: u32 = 1,
    sequence: u64,
    manifest_offset: u64,
    vlog_epoch: types.Epoch,
};

pub const Manager = struct {
    // TODO: implement
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) Manager {
        _ = allocator;
        _ = db_path;
        return .{};
    }
    pub fn deinit(self: *Manager) void {
        _ = self;
    }
    pub fn load(self: *Manager) !void {
        _ = self;
    }
};
