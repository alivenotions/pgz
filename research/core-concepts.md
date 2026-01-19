# Core Concepts for pgz

This document explains the fundamental concepts behind pgz's design decisions.

## 1. What happens if power fails mid-write?

### The problem

When you call `write()`, data goes to multiple layers:
```
Your code → Kernel page cache → Disk controller cache → Physical media
```

Power can fail at any point. If it fails after the kernel says "done" but before data hits physical media, your data is gone but your code thinks it succeeded.

### Traditional approach

Databases use Write-Ahead Logging (WAL). Write your intent to a log first, fsync, then modify data. On crash, replay the log.

### Our approach

Append-only design. We never overwrite data. Every write goes to a new location. If we crash mid-write:
- The old data is still intact (we didn't overwrite it)
- The partial new write is detectable via CRC mismatch or truncated length
- Recovery just scans for the last valid record

### Why this is better for SSDs

- No random writes (SSDs hate those - causes write amplification inside the device)
- No need for complex WAL replay logic
- Simpler crash recovery: just scan forward, stop at first invalid record

### Research pointers

- Read about "torn writes" - when a 4KiB write only partially completes
- Look up "power loss protection" (PLP) in enterprise SSDs
- Study how LevelDB/RocksDB handle crash recovery

---

## 2. Why pad everything to 4KiB even for small values?

### The hardware reality

```
SSD internal page size: 4-16 KiB (can't write smaller)
OS page size: 4 KiB
Disk sector size: 512B or 4KiB
```

If you write 100 bytes to an SSD, internally it must:
1. Read the entire 4KiB page containing those bytes
2. Modify the 100 bytes in memory
3. Write the entire 4KiB page back

This is called **read-modify-write** and it's slow.

### With O_DIRECT / F_NOCACHE

The OS bypasses its page cache entirely. Your buffer goes straight to the device. But the device *requires* aligned writes. Unaligned = error or terrible performance.

### Why we pad

```
┌──────────┬───────────┬─────────────────┬────────────────────┐
│ len: u32 │ crc32c: u32 │ payload: bytes │ zero-pad → 4KiB  │
└──────────┴───────────┴─────────────────┴────────────────────┘
```
- Every record starts at a 4KiB boundary
- Every record is a multiple of 4KiB
- Recovery is simple: scan at 4KiB offsets, check CRC at each
- No read-modify-write penalty

### The tradeoff

Space inefficiency for small values. A 10-byte value wastes ~4KB. This is why `plan.md` mentions possibly inlining small values into the LSM key later.

### Research pointers

- Read about O_DIRECT on Linux, F_NOCACHE on macOS
- Look up "FTL" (Flash Translation Layer) to understand SSD internals
- Search "write amplification factor" (WAF) - this is why alignment matters

---

## 3. What's the difference between `fsync` and `F_FULLFSYNC` on macOS?

### The lie of fsync

```c
fsync(fd);  // "Flush to stable storage"
```

On macOS, `fsync` only guarantees data reaches the **disk's write cache**, not the physical media. The disk can still lose it on power failure.

### F_FULLFSYNC

```c
fcntl(fd, F_FULLFSYNC, 0);  // Actually flush to physical media
```

This sends a "flush cache" command to the drive itself. It's slower but actually durable.

### Linux equivalent

`fsync()` is usually honest on Linux (with proper mount options), but `fdatasync()` is faster when you don't need metadata durability.

### Why this matters

```
Your code: write() → fsync() → "committed!"
Reality:   data sitting in drive cache → power fails → data gone

Your code: write() → F_FULLFSYNC → "committed!"  
Reality:   data on physical media → power fails → data safe
```

### Research pointers

- Read the famous paper "All File Systems Are Not Created Equal" (OSDI '14)
- Look up "write barriers" in storage systems
- Search for MySQL/PostgreSQL durability bugs related to fsync

---

## 4. Why LSM + vLog Instead of Traditional B-Trees?

### Traditional database (PostgreSQL, MySQL InnoDB)

```
B-tree pages stored in fixed locations
    ↓
Update = read page, modify in place, write back
    ↓
Problem: Random writes everywhere
    ↓
SSDs: Internal garbage collection goes crazy, WAF explodes
```

### Our LSM + vLog approach

```
All writes are sequential appends
    ↓
Keys go to memory (MemTable), periodically flush to sorted files
    ↓
Values go to append-only log (vLog)
    ↓
SSDs: Sequential writes only, minimal internal GC, low WAF
```

### The key insight

**SSDs are not disks.** They pretend to be, but internally:
- They can't overwrite in place (must erase entire blocks first)
- Erases are slow and wear out the device
- Random small writes cause massive internal write amplification

By designing for sequential, aligned, append-only writes, we work *with* the hardware instead of against it.

### The tradeoff

- **Reads are more complex:** Must check MemTable, then multiple SSTable levels
- **Background work:** Compaction to merge levels, GC to reclaim vLog space
- **More code:** LSM is inherently more complex than a B-tree

But for write-heavy workloads on SSDs, the performance difference is dramatic.

---

## 5. Key-Value Separation (WiscKey)

### Traditional LSM problem

In a standard LSM tree (like LevelDB), keys AND values are stored together in sorted files. During compaction, the entire file is rewritten - including all values.

For large values (1KB+), this means massive write amplification during compaction.

### Our solution

Store only keys (with pointers) in the LSM tree. Store actual values in a separate append-only log (vLog).

```
LSM Tree:  key → ValuePointer { segment, offset, len }
vLog:      actual value bytes at that location
```

During compaction, we only rewrite small keys, not large values.

### When this wins

- Values >= 512 bytes: significant WAF reduction
- Write-heavy workloads: less compaction I/O
- Large values: dramatic improvement

### When this loses

- Tiny values: overhead of indirection
- Scan-heavy workloads: values not co-located with keys
- Point reads: extra I/O to fetch value from vLog

---

## Reading List

### Essential papers

1. **WiscKey** (FAST '16) - "Separating Keys from Values in SSD-conscious Storage"
   - https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf
   - The KV-separation idea we're implementing

2. **LSM-tree original paper** (1996) - "The Log-Structured Merge-Tree"
   - http://www.cs.umb.edu/~poneil/lsmtree.pdf
   - Understand the fundamentals

3. **All File Systems Are Not Created Equal** (OSDI '14)
   - Crash consistency bugs in real applications
   - Why fsync semantics matter

### Books

4. **"Designing Data-Intensive Applications"** by Martin Kleppmann
   - Chapter 3: Storage and Retrieval
   - Excellent LSM vs B-tree comparison

### Implementation references

5. **RocksDB Wiki** - https://github.com/facebook/rocksdb/wiki
   - Production LSM implementation details
   - Compaction strategies, bloom filters, etc.

6. **LevelDB source code** - https://github.com/google/leveldb
   - Clean, readable LSM implementation
   - Good starting point for understanding the concepts

### SSD internals

7. **"Coding for SSDs"** series on codecapsule.com
   - https://codecapsule.com/2014/02/12/coding-for-ssds-part-1-introduction-and-table-of-contents/
   - How SSDs actually work internally

8. **"What Every Programmer Should Know About Memory"** by Ulrich Drepper
   - https://people.freebsd.org/~lstewart/articles/cpumemory.pdf
   - Deep dive on memory hierarchy (useful for buffer cache understanding)

---

## Implementation Order

### Start with `io.zig` because:

1. It's self-contained (no dependencies on other modules)
2. You'll immediately understand alignment constraints
3. Every other module depends on it
4. Tests are straightforward: write bytes, read bytes, verify

### Then `vlog.zig`:

Once you have `io.zig` working with real files, `vlog.zig` becomes "just" adding headers and checksums to the bytes you're already writing.

### Then `sstable.zig`:

Block encoding/decoding, fence index. This is where you'll really understand the on-disk format from `plan.md`.

### Then `manifest.zig`:

Dual superblock swap. This teaches you atomic metadata updates.

---

## Questions to Ask Yourself

As you implement, keep asking:

1. **What happens if power fails right here?**
   - After write() but before fsync?
   - After fsync but before updating the pointer?
   - Mid-way through a multi-step operation?

2. **Is this I/O aligned?**
   - Buffer address divisible by 4096?
   - File offset divisible by 4096?
   - Length a multiple of 4096?

3. **Can I recover from this?**
   - If I crash now, can I detect the incomplete state?
   - Is there enough information to roll back or roll forward?

4. **What's the write amplification?**
   - How many bytes hit the disk for each byte of user data?
   - Is there a way to reduce it?
