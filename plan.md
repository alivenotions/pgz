# SSD-First Storage Layer Architecture Plan

## Executive Summary

This document outlines the architectural plan for building a Postgres-compatible database with an SSD-optimized storage layer. Unlike traditional databases designed for HDDs (which minimize random seeks), this design leverages SSD characteristics: fast random reads, parallel I/O, and sensitivity to write amplification.

## Design Principles

### 1. SSD-First Optimizations

**Exploit SSD Strengths:**
- Fast random reads (~100 µs latency vs ~10 ms for HDD)
- High parallelism (multiple channels/dies)
- Uniform access time (no seek penalty)
- High bandwidth for sequential operations

**Mitigate SSD Weaknesses:**
- Minimize write amplification
- Avoid small random writes (use larger block writes)
- Implement wear-leveling awareness
- Optimize for flash page/block alignment

### 2. Storage Engine Architecture

**LSM-Tree Based Storage (Not B-Tree)**

Traditional databases use B-trees optimized for HDDs. We'll use Log-Structured Merge Trees (LSM):

**Why LSM for SSDs:**
- Converts random writes into sequential writes (reduces write amplification)
- Better write throughput (batch writes)
- Leverages SSD's fast random read capability for compaction
- Reduces space amplification compared to naive log-structured designs

**Core Components:**

```
┌─────────────────────────────────────────────────────────┐
│                  Query Layer (Postgres Compatible)       │
├─────────────────────────────────────────────────────────┤
│                  MVCC Transaction Manager                │
├─────────────────────────────────────────────────────────┤
│                  LSM Storage Engine                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │ MemTable │→ │  WAL     │  │  SSTable Levels      │  │
│  │ (Active) │  │ (Durable)│  │  L0, L1, L2...       │  │
│  └──────────┘  └──────────┘  └──────────────────────┘  │
├─────────────────────────────────────────────────────────┤
│                  Block Cache / Buffer Pool               │
├─────────────────────────────────────────────────────────┤
│           Async I/O Layer (io_uring/kqueue)             │
└─────────────────────────────────────────────────────────┘
```

## Architecture Components

### 3. Storage Layer Design

#### 3.1 MemTable (In-Memory Write Buffer)

- **Structure:** Skip list or B+ tree in memory
- **Size:** 64-256 MB (configurable)
- **Purpose:** Absorb writes, batch before flushing to disk
- **Benefits:** Converts many small writes into one large sequential write

#### 3.2 Write-Ahead Log (WAL)

- **Format:** Sequential append-only log
- **Block Size:** 4KB or 8KB (aligned with SSD page size)
- **Durability:** fsync on commit (configurable)
- **Optimization:** Group commit to batch fsync calls
- **Purpose:** Crash recovery, durability guarantees

#### 3.3 SSTable (Sorted String Table) Files

**Structure:**
```
┌─────────────────────────────────────┐
│ Data Blocks (4KB - 64KB each)       │
│ - Sorted key-value pairs            │
│ - Compressed (LZ4/Zstd)             │
├─────────────────────────────────────┤
│ Index Block                          │
│ - Block offset index                │
│ - Bloom filters per block           │
├─────────────────────────────────────┤
│ Footer (metadata)                   │
└─────────────────────────────────────┘
```

**Block Size Rationale:**
- SSD page size: 4KB-16KB
- Flash block size: 128KB-256KB
- Optimal read: 16KB-64KB (balance between amplification and throughput)

**Levels:**
- L0: Direct MemTable flushes (may overlap)
- L1-L6: Progressively larger, non-overlapping (10x size multiplier)
- Target sizes: L0=256MB, L1=256MB, L2=2.5GB, L3=25GB, etc.

#### 3.4 Compaction Strategy

**Leveled Compaction (RocksDB-style):**

1. **Minor Compaction:** MemTable → L0 SSTable
2. **Major Compaction:** Merge overlapping SSTables across levels

**SSD Optimizations:**
- Parallel compaction threads (exploit SSD parallelism)
- Direct I/O to bypass page cache
- Larger block sizes for compaction I/O
- Bloom filters to minimize read amplification during compaction

**Write Amplification Target:** < 10x (industry standard)

### 4. Indexing Strategy

#### 4.1 Primary Index (LSM-based)

- Row identifier (ROWID) → tuple location
- Clustered on primary key
- Stored in LSM tree structure

#### 4.2 Secondary Indexes

**Options to Evaluate:**

**Option A: Separate LSM per Index**
- Each index is its own LSM tree
- Simple but higher write amplification

**Option B: Index Organized Tables**
- Store index key → primary key mapping
- Requires primary key lookup (2 reads per query)
- Better for SSD (random reads are cheap)

**Recommendation:** Start with Option B, enables fast point lookups leveraging SSD random read performance.

#### 4.3 Index Structures

**Bloom Filters:**
- Per-SSTable bloom filter
- False positive rate: 1%
- Saves unnecessary disk reads

**Block Index:**
- Sparse index in SSTable
- Binary search to locate block
- Full scan within block

### 5. MVCC Implementation (Postgres Compatibility)

**Transaction ID Management:**
- 32-bit or 64-bit transaction IDs (XID)
- XID stored with each tuple version

**Tuple Versioning:**
```
Tuple Header:
  - xmin (creating transaction ID)
  - xmax (deleting transaction ID)
  - command ID
  - tuple visibility bitmap
```

**Version Storage:**
- Append-only approach (fits LSM model)
- Old versions kept until vacuum
- Tombstones for deleted tuples

**Snapshot Isolation:**
- Transaction snapshot = XID + active transaction list
- Visibility check per tuple

**Garbage Collection:**
- Integrate with compaction process
- Remove old tuple versions during compaction
- Vacuum can trigger compaction on specific SSTables

### 6. Buffer Pool / Block Cache

**Design:**
- LRU or Clock eviction policy
- Separate cache for index blocks vs data blocks
- Size: Configurable (default 25% of RAM)

**SSD-Specific Optimizations:**
- Smaller buffer pool than traditional databases (SSD is fast)
- Prioritize caching hot index blocks
- Use direct I/O for sequential scans (bypass cache)

### 7. I/O Layer

**Cross-Platform Async I/O:**

**Linux: io_uring**
- Modern async I/O interface (kernel 5.1+)
- Bypass kernel page cache for data files
- True asynchronous I/O with submission/completion queues
- Batch I/O operations
- Minimal system call overhead

**macOS/BSD: kqueue**
- Event notification interface
- Async file I/O via EVFILT_READ/EVFILT_WRITE
- Can combine with aio (POSIX async I/O) for better performance
- Similar batching capabilities to io_uring

**Fallback: POSIX AIO**
- Cross-platform async I/O (aio_read/aio_write)
- Available on both Linux and macOS
- Less performant than io_uring/kqueue but widely supported

**Common optimizations:**
- Direct I/O (O_DIRECT on Linux, F_NOCACHE on macOS)
- Aligned I/O to SSD page boundaries (4KB/8KB/16KB)
- Batched operations to reduce syscall overhead
- Multiple I/O threads for parallelism

**Benefits:**
- Predictable performance across platforms
- Exploit SSD's internal parallelism
- Reduce CPU overhead
- Platform-specific optimizations where available

### 8. Page Layout

**Fixed Page Size: 16KB** (vs Postgres default 8KB)

**Rationale:**
- Better amortization of metadata overhead
- Align with common SSD page sizes (8-16KB)
- Fewer total pages = smaller indexes
- Still reasonable for random access on SSD

**Page Structure:**
```
┌──────────────────────────────┐
│ Page Header (64 bytes)        │
│ - LSN, checksum, flags        │
├──────────────────────────────┤
│ Item Pointer Array            │
│ - Offset, length pairs        │
├──────────────────────────────┤
│          Free Space           │
├──────────────────────────────┤
│ Tuples (grow upward)          │
│ - MVCC headers                │
│ - User data                   │
└──────────────────────────────┘
```

## Postgres Compatibility Layer

### 9. Wire Protocol

**Implementation:**
- Postgres wire protocol v3.0
- Support for basic SQL queries (SELECT, INSERT, UPDATE, DELETE)
- Connection management
- Authentication (start with MD5, add SCRAM-SHA-256)

**Components:**
- Protocol parser
- Query planner
- Executor
- Result formatter

### 10. SQL Engine

**Parser:**
- Use existing parser (pg_query or custom)
- Generate Abstract Syntax Tree (AST)

**Planner:**
- Cost-based optimization
- Index selection
- Join algorithms (hash, nested loop, merge)
- Cost model tuned for SSD characteristics

**Executor:**
- Volcano-style iterator model or vectorized execution
- Push-down predicates to storage layer

### 11. Catalog / System Tables

**Metadata Storage:**
- pg_class, pg_attribute, pg_index, etc.
- Store in same LSM engine
- Cached in memory for fast access

## Implementation Phases

### Phase 1: Foundation (Weeks 1-4)
- Basic storage layer (MemTable, WAL, SSTable format)
- Simple LSM with manual compaction
- File I/O abstractions

### Phase 2: Core Engine (Weeks 5-10)
- Automatic compaction
- Block cache
- MVCC basics
- Simple query execution

### Phase 3: Postgres Protocol (Weeks 11-14)
- Wire protocol implementation
- SQL parser integration
- Basic query planner

### Phase 4: Indexing (Weeks 15-18)
- Secondary indexes
- Bloom filters
- Query optimization

### Phase 5: Advanced Features (Weeks 19-24)
- Transactions (BEGIN/COMMIT/ROLLBACK)
- Vacuum/garbage collection
- Performance tuning
- Benchmarking

### Phase 6: Production Hardening (Weeks 25-30)
- Crash recovery
- Replication
- Backup/restore
- Monitoring and observability

## Performance Targets

### Benchmarks (Compared to Postgres on SSD)

**Write Performance:**
- 2-5x higher write throughput
- Lower 99th percentile write latency
- Target: 100K writes/sec on commodity SSD

**Read Performance:**
- Similar point query performance
- Better range scan throughput (sequential I/O)
- Target: < 1ms p99 for point queries

**Space Efficiency:**
- Space amplification < 1.5x
- Write amplification < 10x

## Technology Stack

**Language:** Zig
- Manual memory management
- Performance
- Interop with C libraries
- Zero-cost abstractions
- Cross-platform support (Linux, macOS, BSD)

**Key Libraries:**
- **Async I/O:**
  - io_uring (Linux via liburing)
  - kqueue (macOS/BSD, built-in)
  - POSIX AIO fallback (cross-platform)
- **Compression:** LZ4 or Zstandard
- **Checksums:** xxHash or CRC32C
- **SQL Parsing:** pg_query (C library) or custom parser

**Platform-Specific Features:**
- **Linux:** io_uring, O_DIRECT, fallocate
- **macOS:** kqueue, F_NOCACHE, F_PREALLOCATE
- **Common:** mmap, fsync, posix_fadvise/fcntl

## Risk Mitigation

### Technical Risks

1. **Write Amplification Too High**
   - Mitigation: Tune compaction parameters, add write buffer

2. **Read Amplification from LSM**
   - Mitigation: Aggressive bloom filter usage, larger blocks

3. **Complexity of MVCC + LSM**
   - Mitigation: Start simple, iterate based on testing

4. **Postgres Compatibility Gaps**
   - Mitigation: Focus on core features, document limitations

### Performance Risks

1. **Compaction CPU Overhead**
   - Mitigation: Parallel compaction, rate limiting

2. **Memory Usage**
   - Mitigation: Configurable MemTable size, buffer pool tuning

## Success Metrics

1. **Correctness:** Pass subset of Postgres regression tests
2. **Performance:** 2x write throughput vs Postgres on SSD
3. **Efficiency:** < 10x write amplification
4. **Compatibility:** Support 80% of common SQL queries
5. **Reliability:** No data loss on crash (with WAL)

## References

- LSM-Tree: "The Log-Structured Merge-Tree" (O'Neil et al.)
- RocksDB Design: Meta's RocksDB wiki
- Postgres Internals: "The Internals of PostgreSQL"
- SSD Characteristics: "Design Tradeoffs for SSD Performance" (Agrawal et al.)
- WiscKey: "WiscKey: Separating Keys from Values in SSD-conscious Storage"

## Conclusion

This architecture leverages SSD strengths (fast random reads, parallelism) while mitigating weaknesses (write amplification). The LSM-tree approach provides better write performance than traditional B-tree designs, and the integration with MVCC enables Postgres compatibility. The phased implementation allows for iterative development and validation.
