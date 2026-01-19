//! C API for FFI with Go.
//!
//! This module exposes the database functionality via C-compatible functions
//! that can be called from Go using cgo.

const std = @import("std");
const db_mod = @import("db.zig");
const txn_mod = @import("txn.zig");

const DB = db_mod.DB;
const Transaction = txn_mod.Transaction;

/// Global allocator for C API allocations.
/// Using GeneralPurposeAllocator for safety; could switch to c_allocator for production.
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// =============================================================================
// Error Codes
// =============================================================================

pub const PGZ_OK: c_int = 0;
pub const PGZ_ERR: c_int = -1;
pub const PGZ_NOT_FOUND: c_int = 1;

// =============================================================================
// Database Operations
// =============================================================================

/// Opens a database at the given path.
/// Returns null on error.
export fn pgz_open(path: [*:0]const u8) ?*DB {
    const path_slice = std.mem.span(path);
    return db_mod.DB.open(allocator, path_slice, .{}) catch null;
}

/// Closes a database and frees its resources.
export fn pgz_close(database: ?*DB) void {
    if (database) |d| {
        d.close();
    }
}

// =============================================================================
// Transaction Operations
// =============================================================================

/// Begins a new transaction.
/// Returns null on error.
export fn pgz_txn_begin(database: ?*DB) ?*Transaction {
    const d = database orelse return null;
    return d.txn_mgr.begin() catch null;
}

/// Commits a transaction.
/// Returns PGZ_OK on success, PGZ_ERR on failure.
export fn pgz_txn_commit(database: ?*DB, txn: ?*Transaction) c_int {
    const d = database orelse return PGZ_ERR;
    const t = txn orelse return PGZ_ERR;
    _ = d.txn_mgr.commit(t) catch return PGZ_ERR;
    return PGZ_OK;
}

/// Aborts a transaction.
export fn pgz_txn_abort(database: ?*DB, txn: ?*Transaction) void {
    const d = database orelse return;
    const t = txn orelse return;
    d.txn_mgr.abort(t);
}

// =============================================================================
// Key-Value Operations
// =============================================================================

/// Gets a value by key within a transaction.
/// On success, allocates memory for the value and sets out_val and out_len.
/// Caller must free the returned memory with pgz_free().
/// Returns: PGZ_OK (found), PGZ_NOT_FOUND, or PGZ_ERR.
export fn pgz_get(
    database: ?*DB,
    _: ?*Transaction, // txn - unused for now
    key: [*]const u8,
    key_len: usize,
    out_val: *?[*]u8,
    out_len: *usize,
) c_int {
    const d = database orelse return PGZ_ERR;
    if (key_len == 0) return PGZ_ERR;

    const key_slice = key[0..key_len];

    // Allocate buffer for result
    var buf: [64 * 1024]u8 = undefined; // 64KB max value for now
    const result = d.get(key_slice, &buf) catch return PGZ_ERR;

    if (result) |val| {
        // Allocate memory that Go can free
        const out_buf = allocator.alloc(u8, val.len) catch return PGZ_ERR;
        @memcpy(out_buf, val);
        out_val.* = out_buf.ptr;
        out_len.* = val.len;
        return PGZ_OK;
    }

    out_val.* = null;
    out_len.* = 0;
    return PGZ_NOT_FOUND;
}

/// Puts a key-value pair within a transaction.
/// Returns PGZ_OK on success, PGZ_ERR on failure.
export fn pgz_put(
    database: ?*DB,
    _: ?*Transaction, // txn - unused for now
    key: [*]const u8,
    key_len: usize,
    val: [*]const u8,
    val_len: usize,
) c_int {
    const d = database orelse return PGZ_ERR;
    if (key_len == 0) return PGZ_ERR;

    const key_slice = key[0..key_len];
    const val_slice = val[0..val_len];

    d.put(key_slice, val_slice) catch return PGZ_ERR;
    return PGZ_OK;
}

/// Deletes a key within a transaction.
/// Returns PGZ_OK on success, PGZ_ERR on failure.
export fn pgz_delete(
    database: ?*DB,
    _: ?*Transaction, // txn - unused for now
    key: [*]const u8,
    key_len: usize,
) c_int {
    const d = database orelse return PGZ_ERR;
    if (key_len == 0) return PGZ_ERR;

    const key_slice = key[0..key_len];
    d.delete(key_slice) catch return PGZ_ERR;
    return PGZ_OK;
}

// =============================================================================
// Iterator Operations
// =============================================================================

pub const Iterator = struct {
    // TODO: implement actual iterator state
    started: bool = false,
    exhausted: bool = false,
};

/// Creates an iterator for scanning a key range.
/// Returns null on error.
export fn pgz_scan(
    _: ?*DB, // database
    _: ?*Transaction, // txn
    _: [*]const u8, // start_key
    _: usize, // start_len
    _: [*]const u8, // end_key
    _: usize, // end_len
) ?*Iterator {
    const iter = allocator.create(Iterator) catch return null;
    iter.* = .{};
    return iter;
}

/// Advances the iterator and returns the next key-value pair.
/// Returns PGZ_OK if a value was returned, PGZ_NOT_FOUND if exhausted, PGZ_ERR on error.
export fn pgz_iter_next(
    iter: ?*Iterator,
    _: *?[*]u8, // out_key
    _: *usize, // out_key_len
    _: *?[*]u8, // out_val
    _: *usize, // out_val_len
) c_int {
    const it = iter orelse return PGZ_ERR;
    if (it.exhausted) return PGZ_NOT_FOUND;

    // TODO: implement actual iteration
    it.exhausted = true;
    return PGZ_NOT_FOUND;
}

/// Closes an iterator and frees its resources.
export fn pgz_iter_close(iter: ?*Iterator) void {
    if (iter) |it| {
        allocator.destroy(it);
    }
}

// =============================================================================
// Memory Management
// =============================================================================

/// Frees memory allocated by pgz_get or pgz_iter_next.
export fn pgz_free(ptr: ?[*]u8, len: usize) void {
    if (ptr) |p| {
        if (len > 0) {
            allocator.free(p[0..len]);
        }
    }
}

// =============================================================================
// Utility
// =============================================================================

/// Returns the library version string.
export fn pgz_version() [*:0]const u8 {
    return "0.1.0";
}
