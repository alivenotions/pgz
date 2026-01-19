//! High-level database API.

const std = @import("std");
const types = @import("types.zig");
const vlog = @import("vlog.zig");
const lsm = @import("lsm.zig");
const txn_mod = @import("txn.zig");
const manifest = @import("manifest.zig");

pub const Options = struct {
    create_if_missing: bool = true,
    error_if_exists: bool = false,
    sync_writes: bool = false,
};

pub const DB = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    options: Options,
    vlog_writer: vlog.Writer,
    vlog_reader: vlog.Reader,
    tree: lsm.Tree,
    txn_mgr: txn_mod.Manager,
    manifest_mgr: manifest.Manager,

    pub fn open(allocator: std.mem.Allocator, path: []const u8, options: Options) !*DB {
        const db = try allocator.create(DB);
        db.* = .{
            .allocator = allocator,
            .path = path,
            .options = options,
            .vlog_writer = vlog.Writer.init(allocator, 0),
            .vlog_reader = vlog.Reader.init(allocator),
            .tree = lsm.Tree.init(allocator),
            .txn_mgr = txn_mod.Manager.init(allocator),
            .manifest_mgr = manifest.Manager.init(allocator, path),
        };
        return db;
    }

    pub fn close(self: *DB) void {
        self.allocator.destroy(self);
    }

    pub fn put(self: *DB, key: []const u8, value: []const u8) !void {
        _ = self;
        _ = key;
        _ = value;
        @panic("TODO: implement");
    }

    pub fn get(self: *DB, key: []const u8, buf: []u8) !?[]const u8 {
        _ = self;
        _ = key;
        _ = buf;
        return null;
    }

    pub fn delete(self: *DB, key: []const u8) !void {
        _ = self;
        _ = key;
    }

    pub fn flush(self: *DB) !void {
        _ = self;
    }

    pub fn sync(self: *DB) !void {
        _ = self;
    }
};
