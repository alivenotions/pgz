//! Core type definitions for the pgz storage engine.

const std = @import("std");

// =============================================================================
// Constants
// =============================================================================

pub const PageSize: usize = 4096;
pub const DefaultBlockSize: usize = 32 * 1024;
pub const MaxKeySize: u16 = 64 * 1024;
pub const MaxValueSize: u32 = 1024 * 1024 * 1024;
pub const DefaultSegmentSize: u64 = 256 * 1024 * 1024;

// =============================================================================
// Identifier Types
// =============================================================================

pub const SegmentId = u32;
pub const Offset = u64;
pub const Length = u32;
pub const Epoch = u64;
pub const TransactionId = u64;
pub const Timestamp = u64;
pub const Level = u8;
pub const MaxLevel: Level = 7;

// =============================================================================
// Value Pointer
// =============================================================================

pub const ValuePointer = struct {
    segment: SegmentId,
    offset: Offset,
    len: Length,

    pub const Null: ValuePointer = .{ .segment = 0, .offset = 0, .len = 0 };
    pub const EncodedSize: usize = 16;

    pub fn isNull(self: ValuePointer) bool {
        return self.segment == 0 and self.offset == 0 and self.len == 0;
    }
};

// =============================================================================
// Alignment Helpers
// =============================================================================

pub fn alignUp(n: usize, alignment: usize) usize {
    return (n + alignment - 1) & ~(alignment - 1);
}

pub fn isAligned(n: usize, alignment: usize) bool {
    return (n & (alignment - 1)) == 0;
}

pub fn isPtrAligned(ptr: anytype, alignment: usize) bool {
    return isAligned(@intFromPtr(ptr), alignment);
}

// =============================================================================
// Tests
// =============================================================================

test "alignUp" {
    try std.testing.expectEqual(@as(usize, 4096), alignUp(1, 4096));
    try std.testing.expectEqual(@as(usize, 4096), alignUp(4096, 4096));
    try std.testing.expectEqual(@as(usize, 8192), alignUp(4097, 4096));
}
