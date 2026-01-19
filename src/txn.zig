//! Transaction management and MVCC (Snapshot Isolation).

const std = @import("std");
const types = @import("types.zig");

pub const Status = enum { active, committed, aborted };

pub const Transaction = struct {
    id: types.TransactionId,
    read_ts: types.Timestamp,
    status: Status = .active,

    pub fn init(allocator: std.mem.Allocator, id: types.TransactionId, read_ts: types.Timestamp) Transaction {
        _ = allocator;
        return .{ .id = id, .read_ts = read_ts };
    }
    pub fn deinit(self: *Transaction) void {
        _ = self;
    }
    pub fn recordWrite(self: *Transaction, key: []const u8, vptr: types.ValuePointer) !void {
        _ = self;
        _ = key;
        _ = vptr;
    }
    pub fn recordDelete(self: *Transaction, key: []const u8) !void {
        _ = self;
        _ = key;
    }
};

pub const Manager = struct {
    pub fn init(allocator: std.mem.Allocator) Manager {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *Manager) void {
        _ = self;
    }
    pub fn begin(self: *Manager) !*Transaction {
        _ = self;
        @panic("TODO: implement");
    }
    pub fn commit(self: *Manager, txn: *Transaction) !types.Timestamp {
        _ = self;
        _ = txn;
        @panic("TODO: implement");
    }
    pub fn abort(self: *Manager, txn: *Transaction) void {
        _ = self;
        _ = txn;
    }
};
