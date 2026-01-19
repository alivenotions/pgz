//! CRC32C (Castagnoli) checksum for data integrity.

const std = @import("std");

const Polynomial: u32 = 0x82F63B78;

const crc_table: [256]u32 = blk: {
    @setEvalBranchQuota(5000);
    var table: [256]u32 = undefined;
    for (0..256) |i| {
        var crc: u32 = @intCast(i);
        for (0..8) |_| {
            crc = if (crc & 1 != 0) (crc >> 1) ^ Polynomial else crc >> 1;
        }
        table[i] = crc;
    }
    break :blk table;
};

pub fn crc32c(data: []const u8) u32 {
    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc = (crc >> 8) ^ crc_table[(crc ^ byte) & 0xFF];
    }
    return crc ^ 0xFFFFFFFF;
}

test "crc32c known vector" {
    try std.testing.expectEqual(@as(u32, 0xE3069283), crc32c("123456789"));
}
