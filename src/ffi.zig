const std = @import("std");
const db_mod = @import("db.zig");

// C-compatible error codes
pub const ErrorCode = enum(c_int) {
    OK = 0,
    NOT_FOUND = 1,
    OUT_OF_MEMORY = 2,
    INVALID_ARG = 3,
    UNKNOWN = 99,
};

// Opaque handle to hide Zig implementation from C/Go
pub const DBHandle = opaque {};

// Global allocator for FFI layer
// In production, you might want per-database allocators
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

/// Open/create a new database instance
/// @param handle: Output parameter for the database handle
/// @return ErrorCode indicating success or failure
export fn pgz_db_open(handle: *?*DBHandle) ErrorCode {
    const db_ptr = allocator.create(db_mod.DB) catch {
        return ErrorCode.OUT_OF_MEMORY;
    };

    db_ptr.* = db_mod.DB.init(allocator) catch {
        allocator.destroy(db_ptr);
        return ErrorCode.OUT_OF_MEMORY;
    };

    handle.* = @ptrCast(db_ptr);
    return ErrorCode.OK;
}

/// Close and free a database instance
/// @param handle: Database handle to close
export fn pgz_db_close(handle: *DBHandle) void {
    const db_ptr: *db_mod.DB = @ptrCast(@alignCast(handle));
    db_ptr.deinit();
    allocator.destroy(db_ptr);
}

/// Store a key-value pair
/// @param handle: Database handle
/// @param key: Pointer to key bytes
/// @param key_len: Length of key
/// @param value: Pointer to value bytes
/// @param value_len: Length of value
/// @return ErrorCode indicating success or failure
export fn pgz_put(
    handle: *DBHandle,
    key: [*]const u8,
    key_len: usize,
    value: [*]const u8,
    value_len: usize,
) ErrorCode {
    if (key_len == 0) {
        return ErrorCode.INVALID_ARG;
    }

    const db_ptr: *db_mod.DB = @ptrCast(@alignCast(handle));
    const key_slice = key[0..key_len];
    const value_slice = value[0..value_len];

    db_ptr.put(key_slice, value_slice) catch {
        return ErrorCode.OUT_OF_MEMORY;
    };

    return ErrorCode.OK;
}

/// Retrieve a value by key
/// @param handle: Database handle
/// @param key: Pointer to key bytes
/// @param key_len: Length of key
/// @param value_out: Output pointer to value bytes (caller must free with pgz_free)
/// @param value_len_out: Output length of value
/// @return ErrorCode indicating success or failure
export fn pgz_get(
    handle: *DBHandle,
    key: [*]const u8,
    key_len: usize,
    value_out: *?[*]u8,
    value_len_out: *usize,
) ErrorCode {
    if (key_len == 0) {
        return ErrorCode.INVALID_ARG;
    }

    const db_ptr: *db_mod.DB = @ptrCast(@alignCast(handle));
    const key_slice = key[0..key_len];

    const value = db_ptr.get(key_slice);
    if (value == null) {
        return ErrorCode.NOT_FOUND;
    }

    // Allocate memory that Go will free
    const value_copy = allocator.alloc(u8, value.?.len) catch {
        return ErrorCode.OUT_OF_MEMORY;
    };
    @memcpy(value_copy, value.?);

    value_out.* = value_copy.ptr;
    value_len_out.* = value_copy.len;

    return ErrorCode.OK;
}

/// Delete a key-value pair
/// @param handle: Database handle
/// @param key: Pointer to key bytes
/// @param key_len: Length of key
/// @return ErrorCode indicating success or failure (NOT_FOUND if key doesn't exist)
export fn pgz_delete(
    handle: *DBHandle,
    key: [*]const u8,
    key_len: usize,
) ErrorCode {
    if (key_len == 0) {
        return ErrorCode.INVALID_ARG;
    }

    const db_ptr: *db_mod.DB = @ptrCast(@alignCast(handle));
    const key_slice = key[0..key_len];

    const deleted = db_ptr.delete(key_slice);
    if (!deleted) {
        return ErrorCode.NOT_FOUND;
    }

    return ErrorCode.OK;
}

/// Free memory allocated by Zig (for values returned by pgz_get)
/// @param ptr: Pointer to memory to free
/// @param len: Length of memory to free
export fn pgz_free(ptr: [*]u8, len: usize) void {
    const slice = ptr[0..len];
    allocator.free(slice);
}

// Simple test to verify FFI functions work
test "FFI basic operations" {
    var handle: ?*DBHandle = null;

    // Open database
    const open_result = pgz_db_open(&handle);
    try std.testing.expect(open_result == ErrorCode.OK);
    try std.testing.expect(handle != null);

    // Put a value
    const key = "test_key";
    const value = "test_value";
    const put_result = pgz_put(
        handle.?,
        key.ptr,
        key.len,
        value.ptr,
        value.len,
    );
    try std.testing.expect(put_result == ErrorCode.OK);

    // Get the value
    var value_out: ?[*]u8 = null;
    var value_len: usize = 0;
    const get_result = pgz_get(
        handle.?,
        key.ptr,
        key.len,
        &value_out,
        &value_len,
    );
    try std.testing.expect(get_result == ErrorCode.OK);
    try std.testing.expect(value_len == value.len);

    // Verify value content
    const retrieved = value_out.?[0..value_len];
    try std.testing.expectEqualStrings(value, retrieved);

    // Free the retrieved value
    pgz_free(value_out.?, value_len);

    // Delete the key
    const delete_result = pgz_delete(handle.?, key.ptr, key.len);
    try std.testing.expect(delete_result == ErrorCode.OK);

    // Verify it's gone
    const get_result2 = pgz_get(
        handle.?,
        key.ptr,
        key.len,
        &value_out,
        &value_len,
    );
    try std.testing.expect(get_result2 == ErrorCode.NOT_FOUND);

    // Close database
    pgz_db_close(handle.?);
}
