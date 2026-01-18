const std = @import("std");

/// Simple in-memory key-value store for demonstration
pub const DB = struct {
    allocator: std.mem.Allocator,
    data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) !DB {
        return DB{
            .allocator = allocator,
            .data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *DB) void {
        // Free all stored values
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn put(self: *DB, key: []const u8, value: []const u8) !void {
        // Make copies of key and value
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);

        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        // Check if key exists and free old value
        if (self.data.get(key)) |old_value| {
            self.allocator.free(old_value);
        }

        try self.data.put(key_copy, value_copy);
    }

    pub fn get(self: *DB, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn delete(self: *DB, key: []const u8) bool {
        if (self.data.fetchRemove(key)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value);
            return true;
        }
        return false;
    }
};

test "DB basic operations" {
    var db = try DB.init(std.testing.allocator);
    defer db.deinit();

    // Test put and get
    try db.put("name", "Alice");
    const value = db.get("name");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("Alice", value.?);

    // Test overwrite
    try db.put("name", "Bob");
    const value2 = db.get("name");
    try std.testing.expectEqualStrings("Bob", value2.?);

    // Test delete
    const deleted = db.delete("name");
    try std.testing.expect(deleted);
    try std.testing.expect(db.get("name") == null);
}
