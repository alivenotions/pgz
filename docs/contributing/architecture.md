# pgz Architecture

## Module Overview

```
src/
├── types.zig      # Core types, constants, alignment helpers
├── crc32c.zig     # CRC32C checksums for data integrity
├── io.zig         # Platform I/O abstraction (macOS/Linux)
├── vlog.zig       # Value Log: append-only value storage
├── sstable.zig    # SSTable: sorted key blocks
├── manifest.zig   # Superblock + manifest metadata
├── lsm.zig        # LSM tree: MemTable + levels + compaction
├── txn.zig        # Transactions and MVCC
├── db.zig         # High-level DB API
├── root.zig       # Library exports
├── main.zig       # CLI entry point
└── testing.zig    # Test utilities
```

## Data Flow

```
Write path:
  Client → DB.put() → vLog.append() → MemTable.put()
                           ↓
                    ValuePointer stored in LSM

Read path:
  Client → DB.get() → LSM.get() → MemTable → L0 → L1 → ...
                           ↓
                    ValuePointer → vLog.read() → Value
```

## Key Design Decisions

### KV-Separation
Keys stored in LSM tree, values in append-only vLog. Reduces compaction write amplification.

### 4KiB Alignment
All I/O aligned to page size for direct I/O compatibility and SSD efficiency.

### Checksums Everywhere
CRC32C on every on-disk block to detect corruption.

### Append-Only
No in-place updates. Crash recovery is simple: scan for last valid record.

## Implementation Status

| Module | Status | Notes |
|--------|--------|-------|
| types.zig | ✅ Done | Constants, ValuePointer, alignment |
| crc32c.zig | ✅ Done | Working implementation |
| io.zig | 🔲 Interface only | Needs platform implementation |
| vlog.zig | 🔲 Interface only | Needs Writer/Reader impl |
| sstable.zig | 🔲 Interface only | Needs Builder/Reader impl |
| manifest.zig | 🔲 Interface only | Needs Manager impl |
| lsm.zig | 🔲 Interface only | Needs MemTable/Tree impl |
| txn.zig | 🔲 Interface only | Needs Manager impl |
| db.zig | 🔲 Interface only | Needs full impl |
| testing.zig | ✅ Done | TmpDir, assertions |
