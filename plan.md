# SSD-First, PG-Compatible Engine — Implementation Plan (Zig)

> **What is this?** A design document for building a database storage engine from scratch. It speaks PostgreSQL's network protocol (so existing tools like `psql` work), but underneath uses a completely different storage architecture optimized for modern SSDs.

---

## 0. North Star & Non-Goals

### Goal

Build a database that:
- **Speaks PostgreSQL's wire protocol** — clients connect using standard Postgres drivers/tools
- **Supports a SQL subset** — basic queries, not the full Postgres feature set
- **Is flash-native** — designed from the ground up for SSD characteristics
- **Has predictable low tail latency** — the slowest 1% of requests (p99) stay fast
- **Minimizes write amplification (WAF)** — reduces unnecessary writes to extend SSD lifespan

> **What is Write Amplification Factor (WAF)?**
> When you write 1 MB of user data, the storage engine might actually write 3 MB to disk (due to reorganization, compaction, etc.). That's a WAF of 3×. SSDs have limited write endurance, so lower WAF = longer device life and better performance.

### Non-Goals (v1)

These are explicitly out of scope for the first version:

| Non-Goal | Why Defer? |
|----------|-----------|
| Full PG feature parity | Focus on core functionality first; feature parity is years of work |
| Cross-platform async I/O | Start with macOS (your dev machine); add Linux `io_uring` and Windows later |
| Distributed SQL | Single-node first; distribution adds massive complexity |
| Complex joins | Start with simple queries; optimizer is hard |

### Platform Strategy

| Phase | Platform | I/O Stack | Notes |
|-------|----------|-----------|-------|
| **Now** | macOS | kqueue + thread pool, `F_NOCACHE`, `F_FULLFSYNC` | Your dev machine |
| Later | Linux | io_uring, `O_DIRECT`, `fdatasync` | Production servers |
| Maybe | Windows | IOCP, unbuffered I/O | If demand exists |

The I/O layer is abstracted from day one so adding platforms later is straightforward.

---

## 1. Architecture (Flash-Native)

### Core Design Philosophy

**"Keys in LSM; values in an append-only value-log (vLog). No update-in-place."**

This is a **key-value separation** architecture, inspired by [WiscKey](https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf). Here's why:

> **Traditional LSM Problem:** Log-Structured Merge Trees store keys AND values together. When compaction merges files, it rewrites all values even if only keys changed. For large values (1KB+), this causes massive write amplification.
>
> **Our Solution:** Store only keys (with pointers) in the LSM tree. Store actual values in a separate append-only log. During compaction, we only rewrite small keys, not large values.

### System Architecture Diagram

```
Client/psql ─── PG v3 wire ───► SQL layer (minimal planner/executor)
                                      │
                                KV API (get/put/scan, txn)
                                      │
        ┌────────────┬────────────────┴────────────────┬─────────────┐
        │            │                                 │             │
   MemTable    LSM Levels (keys→vptr)            vLog (append)   Commit Log
 (in-memory)    L0..Ln (tiered→leveled)          (values only)   (group commit)
        │            │                                 │             │
        └────────────┴────────── Async I/O Layer ──────┴─────────────┘
                            (kqueue + pread/pwrite, F_NOCACHE, 4KiB-aligned)
```

### Component Breakdown

| Component | What It Does | Why It Exists |
|-----------|--------------|---------------|
| **MemTable** | In-memory buffer for recent writes | Batches many small writes into one large sequential flush |
| **LSM Levels** | On-disk sorted files containing keys → value pointers | Enables efficient key lookups without reading values |
| **vLog** | Append-only file storing actual row values | Separates values from keys to reduce compaction cost |
| **Commit Log** | Durability record for transactions | Ensures committed transactions survive crashes |

> **What is an LSM Tree?**
> A Log-Structured Merge Tree is a write-optimized data structure. Writes go to memory first, then flush to disk as immutable sorted files. Background "compaction" merges these files to maintain read performance. Used by RocksDB, LevelDB, Cassandra, etc.

### Key Invariants

These are rules that must ALWAYS hold — if violated, the system is broken:

1. **4 KiB-aligned I/O only**
   - All disk reads/writes are multiples of 4096 bytes
   - *Why:* SSDs operate on pages (typically 4KB). Unaligned I/O causes read-modify-write cycles, killing performance
   - *How to verify:* Assert alignment at I/O layer; any unaligned access is a bug

2. **Checksums on every on-disk block**
   - Every block includes a CRC32C checksum
   - *Why:* Detect bit rot, firmware bugs, cosmic rays corrupting data
   - *Contrast with:* Some systems only checksum occasionally; we're paranoid

3. **Durability definition**
   - A transaction is durable IFF (if and only if):
     - Its commit record is on stable storage, AND
     - All referenced value appends are on stable storage
   - *Why:* Without this, a crash could leave dangling pointers

4. **Crash recovery = manifest + pointer repair**
   - Never overwrite data in place
   - *Why:* Append-only design means we always have the old version during writes. Crash during write? Old version is intact.
   - *Contrast with:* B-tree databases that update pages in place need complex recovery (WAL replay, torn page detection, etc.)

---

## 2. On-Disk Formats (Stable v1)

> **Why "Stable v1"?**
> Once we commit to a format, changing it requires migration code. Get it right first.

### vLog Record Format

```
┌──────────┬───────────┬─────────────────┬────────────────────┐
│ len: u32 │ crc32c: u32 │ payload: bytes │ zero-pad → 4KiB  │
└──────────┴───────────┴─────────────────┴────────────────────┘
```

- **len** (4 bytes): Payload size in bytes
- **crc32c** (4 bytes): Checksum of the payload
- **payload**: The actual value (row data)
- **zero-pad**: Padding to reach 4KiB alignment

> **Why padding to 4KiB?**
> Even small values get padded. This seems wasteful but:
> 1. Enables O_DIRECT (bypasses kernel page cache)
> 2. Makes recovery simple (scan 4KiB boundaries)
> 3. For small values, we may inline them in the LSM key (see Open Decisions)

### SSTable Block Format

SSTables (Sorted String Tables) store our LSM key data:

```
┌──────────────┬───────────┬────────────────────┬───────────┬────────────┐
│ block_len: u32 │ count: u32 │ entries...       │ crc32c: u32 │ pad→4KiB │
└──────────────┴───────────┴────────────────────┴───────────┴────────────┘
```

Each entry within a block:

```
┌────────────┬─────────┬──────────┬───────────┬───────────┬────────────┐
│ k_len: u16 │ key     │ seg: u32 │ off: u64  │ len: u32  │ epoch: u32 │
└────────────┴─────────┴──────────┴───────────┴───────────┴────────────┘
```

- **key**: The lookup key (e.g., primary key value)
- **seg, off, len**: Value pointer — which vLog segment, byte offset, and length
- **epoch**: Version number for MVCC (more in section 4)

> **What is a vptr (value pointer)?**
> Instead of storing the actual value, we store `(segment_id, offset, length)`. To read the value, seek to that location in the vLog.

### Fence Index Page

A sparse index to find blocks within an SSTable:

```
┌─────────────────────────────────────────────────┬───────────┐
│ sorted array of (first_key_of_block, file_off) │ crc32c    │
└─────────────────────────────────────────────────┴───────────┘
```

- Binary search this index to find which block contains your key
- Then search within the block

### Commit Record

Records which transactions committed:

```
┌───────────┬───────────────┬────────────────┬──────────────┬───────────┐
│ txid: u64 │ commit_ts: u64 │ ptr_count: u32 │ vptrs...     │ crc32c    │
└───────────┴───────────────┴────────────────┴──────────────┴───────────┘
```

### Manifest

The manifest is the "table of contents" for the entire database:

- List of active vLog segments
- LSM level descriptors (which SSTables at which level)
- Current vLog epoch
- Pointer to superblock

> **Atomic updates via superblock swap:**
> We keep TWO copies of the superblock. To update, write to the inactive copy, `fsync`, then atomically update a pointer. If we crash mid-write, we still have the old valid copy.

---

## 3. I/O & OS Scope

### macOS-First Strategy

We're starting on macOS (your dev machine), then adding Linux and Windows later.

| Feature | macOS | Linux (later) | Why |
|---------|-------|---------------|-----|
| **Async I/O** | `kqueue` + thread pool | `io_uring` | Event notification; true async on Linux |
| **Cache bypass** | `F_NOCACHE` via `fcntl()` | `O_DIRECT` | We manage our own cache; avoid double-caching |
| **Sync** | `fsync` / `fcntl(F_FULLFSYNC)` | `fdatasync` / `fsync` | Durability guarantees |
| **Preallocation** | `F_PREALLOCATE` | `fallocate` | Reserve space without writing |

> **macOS vs Linux I/O Differences:**
> - **No O_DIRECT on macOS**: Use `fcntl(fd, F_NOCACHE, 1)` instead. It hints to skip caching but doesn't require aligned buffers (though we align anyway for consistency).
> - **No io_uring on macOS**: Use `kqueue` for event notification + thread pool for actual I/O. Less efficient but works.
> - **F_FULLFSYNC vs fsync**: On macOS, `fsync` only flushes to drive cache. `F_FULLFSYNC` forces write to physical media (like Linux `fsync` on most drives).

### Abstraction Layer

We'll build an I/O abstraction so the rest of the code doesn't care about the platform:

```zig
// io.zig - platform-agnostic interface
pub const AsyncIO = struct {
    // Submits read/write, returns immediately
    pub fn submit(op: IOOp) !void { ... }

    // Waits for completions
    pub fn poll(completions: []Completion) !usize { ... }
};

// Platform backends:
// - macos.zig: kqueue + thread pool + F_NOCACHE
// - linux.zig: io_uring + O_DIRECT (added later)
// - fallback.zig: synchronous pread/pwrite (for testing)
```

> **Why abstract early?**
> It's tempting to "just use macOS APIs directly" but:
> 1. You'll want Linux eventually (production servers)
> 2. Refactoring I/O paths later is painful and error-prone
> 3. The abstraction also helps testing (inject failures, simulate slow I/O)

### Durability Approach

- **Group commit with sync batches**
  - Multiple transactions commit together in a single sync call
  - macOS: Use `fcntl(F_FULLFSYNC)` for true durability
  - Linux: Use `fdatasync` (metadata-only) or `fsync`
  - Reduces sync overhead (sync is expensive: ~1-10ms)

- **Optional FUA (Force Unit Access)** — Linux only
  - Tells the drive "write this immediately, don't cache it"
  - Only used for critical commit points
  - Requires drives with Power Loss Protection (PLP)
  - macOS: Not available; use `F_FULLFSYNC` instead

> **What is Group Commit?**
> Instead of: write tx1, sync, write tx2, sync, write tx3, sync
> We do: write tx1, write tx2, write tx3, sync ALL
> Same durability, 3× less sync overhead.

### Readahead Strategy

- **Adaptive readahead**: Track recent cache misses and latencies
- Lower kernel's default readahead on devices (we know our access patterns better)

### TRIM/Discard

- **Periodic `fstrim`**: Tell SSD about deleted blocks so it can garbage collect
- **Never mount with `discard`**: Synchronous TRIM on every delete is slow; batch it instead

---

## 4. Transactions & MVCC (Snapshot Isolation)

### What is MVCC?

**Multi-Version Concurrency Control** lets readers and writers work simultaneously without blocking each other. Instead of locking a row, we keep multiple versions:

```
Row "user:123":
  Version 1: {name: "Alice", ts: 100}  ← visible to snapshots ts ≥ 100
  Version 2: {name: "Alicia", ts: 200} ← visible to snapshots ts ≥ 200
```

Readers see a consistent snapshot as of their start time.

### Isolation Level: Snapshot Isolation (SI)

> **Why SI and not Serializable?**
> Serializable is the "gold standard" but requires conflict detection, which is complex and has overhead. SI prevents most anomalies (dirty reads, non-repeatable reads, phantom reads) and is what most apps need.

**SI provides:**
- You see a consistent snapshot of the database as of transaction start
- Other transactions' uncommitted or later-committed changes are invisible
- Write-write conflicts are detected (two transactions updating same row = one aborts)

**SI does NOT prevent:**
- Write skew (two transactions read overlapping data, write disjoint data, result is anomalous)

### Implementation Approach

1. **Commit timestamps (HLC OK)**
   - Each transaction gets a commit timestamp
   - HLC = Hybrid Logical Clock (combines wall-clock time with logical counter for ordering)

2. **Writes append new versions to vLog**
   - Never overwrite; always append
   - LSM stores `(key, commit_ts, vptr)`

3. **Deletes are tombstones**
   - A delete is just a write of a special "deleted" marker
   - Actual space reclaimed during garbage collection

4. **Visibility rule**
   ```
   visible IF create_ts ≤ read_ts < delete_ts
   ```
   - `create_ts`: When this version was created
   - `read_ts`: The reader's snapshot timestamp
   - `delete_ts`: When this version was deleted (∞ if not deleted)

### Garbage Collection

**Problem:** Old versions accumulate forever. Need to clean up.

**Solution:**
- Track `global_safe_ts` = oldest active snapshot timestamp
- Versions older than `global_safe_ts` with newer versions can be deleted
- Two places for cleanup:
  - **vLog GC**: Rewrites segments, dropping old versions
  - **LSM compaction**: Drops unreachable keys during merge

---

## 5. LSM Design & Compaction

### LSM Overview

An LSM tree has multiple "levels" of sorted files:

```
Level 0 (L0): Fresh flushes from MemTable (may overlap)
Level 1 (L1): Merged from L0
Level 2 (L2): Merged from L1 (10× larger)
...and so on...
```

### Compaction Policy: Hybrid Tiered → Leveled

| Level | Policy | Why |
|-------|--------|-----|
| L0, L1 | **Tiered** | Fast ingest; accept some read overhead |
| L2+ | **Leveled** | Read-friendly; worth the write cost |

> **Tiered vs Leveled Compaction:**
> - **Tiered**: Multiple overlapping files per level. Writes are fast (less rewriting), reads are slower (check multiple files).
> - **Leveled**: Non-overlapping files per level. Writes rewrite more during compaction, reads only check one file per level.

### Compaction Governor

**Problem:** Background compaction can cause latency spikes by saturating I/O.

**Solution:** Token-bucket rate limiting for both I/O and CPU:
- Compaction must acquire tokens before doing work
- When p95/p99 latencies rise, reduce compaction budget
- Protects user-facing queries from background work

> **What is Token Bucket?**
> Imagine a bucket that fills with tokens at a fixed rate. Each I/O operation requires a token. If bucket is empty, wait. This smooths out bursty work.

### Bloom Filters

- **False Positive Rate (FPR) ≈ 0.1%** by default
- Per-level tuning possible (deeper levels might use different FPR)

> **What is a Bloom Filter?**
> A space-efficient probabilistic data structure. It can tell you "definitely not in set" or "probably in set". For LSM, we check the bloom filter before reading an SSTable — if it says "not here", we skip the I/O.

### Block Sizes

- **32-128 KiB** (always 4 KiB aligned)
- Larger blocks at deeper levels (more sequential access patterns)

> **Why larger blocks at deeper levels?**
> Deeper levels are read less frequently but store more data. Larger blocks amortize metadata overhead and improve sequential throughput.

### Performance Target

**Host WAF ≤ 3×** on mixed OLTP with KB-scale values.

If we measure higher WAF, we tune before adding features. This is a hard constraint.

---

## 6. Secondary Indexes & Execution

### Secondary Index Strategy

Secondary indexes are stored as **separate LSM trees**:

```
Secondary LSM: (index_key, primary_key) → [no value, just mapping]
Primary LSM: (primary_key) → vptr → actual row in vLog
```

**Query flow for indexed lookup:**
1. Search secondary LSM for matching index keys
2. Get list of primary keys
3. Apply remaining predicates (late materialization)
4. Only then fetch values from vLog

> **What is Late Materialization?**
> Don't fetch full row data until you know you need it. If a query has `WHERE indexed_col = X AND other_col = Y`, first use index to get candidates, then filter by `other_col`, then fetch values. Avoids reading values for rows that will be filtered out.

### Execution Engine

- **Vectorized/pipelined scans**: Process batches of rows, not one at a time
- **Projection pushdown**: Only read columns you need
- **Predicate pushdown**: Filter early, before fetching from vLog
- **Joins**: Limited initially (simple nested loop, maybe hash join later)

---

## 7. Buffering Strategy

### Design Philosophy

**"Small DRAM hotset preferred over giant cache; SSD is the fast tier."**

Traditional databases assume disk is slow and RAM is fast, so they cache aggressively. We assume SSD is fast (100µs random read), so we cache less and rely on SSD more.

### Buffer Pools

Two distinct pools:
1. **Key/index blocks**: Hot SSTable blocks and bloom filters
2. **Values**: Recently accessed row data

### Admission Control

Keep NVMe queue depth (QD) near the "latency knee" (≈16-64).

> **What is Queue Depth?**
> How many I/O requests are in-flight to the device. Too low = device idle, wasted throughput. Too high = requests queue up, latency increases exponentially. The "knee" is where latency starts rising sharply.

```
Latency vs Queue Depth:
        ▲
Latency │           ╱
        │         ╱
        │       ╱
        │   ───┘  ← "knee" (sweet spot)
        │───
        └─────────────────► Queue Depth
           16    64   256
```

---

## 8. Replication/Backup (Post-M3)

> **Why post-M3?**
> Get single-node working first. Replication adds significant complexity.

### Physical-ish Streaming Replication

Stream these to replicas:
- Commit log entries
- vLog segment appends
- Manifest deltas

### Snapshots/Backups

- **Manifest pinning**: Prevent GC from deleting segments referenced by a snapshot
- **Copy immutable segments**: Upload to object storage (S3, GCS, etc.)
- Since segments are immutable, backup is just copying files

---

## 9. Observability (First-Class)

Observability is not an afterthought — build it in from the start.

### Metrics to Track

| Metric | Why It Matters |
|--------|----------------|
| **p50/p95/p99 latency histograms** | Understand tail latency distribution |
| **Device queue depth** | Detect saturation |
| **Host WAF** | Measure compaction efficiency |
| **Device WAF** | Measure SSD-internal amplification (if available) |
| **Compaction debt** | How much background work is pending |
| **GC debt** | How much vLog garbage has accumulated |
| **Group-commit window** | Batching efficiency |
| **Per-level read/seek counters** | Identify hot levels |

### SLO Hooks

**SLO = Service Level Objective** (e.g., "p99 latency < 5ms")

When p99 exceeds SLO:
- Compaction governor automatically reduces budgets
- Trade write throughput for read latency
- Alert operator

---

## 10. Performance Gates (Commodity NVMe)

These are **pass/fail criteria** measured on standard NVMe drives (not enterprise PLP drives):

| Gate | Target | How to Test |
|------|--------|-------------|
| Point read p99 | < 1 ms | With warmed index blocks, QD≈16 |
| Sustained ingest | ≥ 100 MB/s | Under active compaction |
| Host WAF | ≤ 4× (goal: ≤3×) | During sustained ingest |
| Crash/restart | < 2 seconds | With default settings |

If we fail a gate, we fix before proceeding. No "we'll optimize later."

---

## 11. Milestones & Exit Criteria

### M0 — Storage Skeleton (macOS, Zig)

**Build:**
- vLog: append/read/scan_last_good
- One SSTable run (no levels yet)
- Commit log
- Superblock/manifest with atomic updates

**Exit Criteria:**
- [ ] Crash-safe (verified with fault injection)
- [ ] 4 KiB-aligned I/O only (asserted, tests fail on violation)
- [ ] Sequential write pattern (no random writes)
- [ ] Basic CLI works: `put`, `get`, `flush`

---

### M1 — LSM + GC + Governor

**Build:**
- Tiered L0/L1 → leveled L2+ compaction
- Bloom filters
- Background compaction
- vLog GC (age + space triggers)
- Remap table (track relocated values)
- Token-bucket throttling

**Exit Criteria:**
- [ ] Ingest ≥ 100 MB/s sustained
- [ ] Host WAF ≤ 4×
- [ ] p99 read latency stable during compaction (no 10× spikes)

---

### M2 — MVCC (SI) + Correctness Suites

**Build:**
- Snapshot isolation with commit timestamps
- Tombstone handling
- Recovery invariants

**Exit Criteria:**
- [ ] SQLLogicTest subset passes
- [ ] [Elle](https://github.com/jepsen-io/elle) consistency tests: no SI anomalies
- [ ] Crash recovery tests pass

> **What is Elle?**
> A tool from Jepsen that analyzes transaction histories to detect isolation anomalies. If Elle finds a problem, you have a concurrency bug.

---

### M3 — PG Wire + Minimal SQL

**Build:**
- PostgreSQL v3 wire protocol
- Authentication (start with password, add SCRAM later)
- SQL support: `CREATE TABLE`, `INSERT`, `SELECT` (PK/range), `BEGIN/COMMIT`

**Exit Criteria:**
- [ ] `psql` connects and works
- [ ] SQLLogicTest subset passes over wire protocol
- [ ] YCSB A/C/F benchmarks run

> **What is YCSB?**
> Yahoo! Cloud Serving Benchmark. Industry-standard workloads for key-value stores.
> - **Workload A**: 50% read, 50% update (heavy writes)
> - **Workload C**: 100% read (cache-like)
> - **Workload F**: 50% read, 50% read-modify-write

---

### M4 — Observability + QoS Polish

**Build:**
- Metrics endpoints (Prometheus-compatible)
- Latency histograms
- SLO-aware compaction
- Basic admin tooling

**Exit Criteria:**
- [ ] Tail latency bounded under sustained background work
- [ ] Operators can monitor system health

---

### (Optional) M5 — ZNS Backend

**Build:**
- Map LSM levels to ZNS zones
- Zone-sequential writes
- GC via zone reset (instead of copy)

> **What is ZNS (Zoned Namespace)?**
> A new SSD interface where the drive is divided into "zones" that must be written sequentially. Gives you control over data placement, reducing device-internal garbage collection.

**Exit Criteria:**
- [ ] Lower device-level WAF compared to block backend
- [ ] Tighter p99 under compaction

---

## 12. Module Map

The project is split into two layers connected via FFI:

### Zig Storage Engine (`/src`)

```
/src
  types.zig        # Constants, errors, type definitions
  crc32c.zig       # Checksum implementation
  io.zig           # Platform I/O abstraction (macOS: kqueue+F_NOCACHE, Linux: io_uring+O_DIRECT)
  vlog.zig         # Value log: append/read/scan, GC hooks
  sstable.zig      # SSTable: block writer/reader, bloom, fence index
  manifest.zig     # Superblock + manifest (atomic replace logic)
  txn.zig          # Transaction: commit log, snapshots, visibility
  lsm.zig          # LSM tree: memtable, flush, compaction scheduler
  db.zig           # High-level API: get/put/scan/txn
  capi.zig         # C API exports for FFI with Go

/include
  pgz.h            # C header for Go cgo bindings
```

### Go Server (`/server`)

```
/server
  cmd/pgz-server/  # Server entry point
  pkg/
    storage/       # Go bindings to Zig via cgo (DB, Txn, Iterator)
    pgwire/        # PostgreSQL v3 protocol (M3)
    parser/        # SQL parser (M3)
    planner/       # Query planner (M3)
```

### FFI Interface

Go calls Zig via cgo. The C API exposes:
- `pgz_open/close` — Database lifecycle
- `pgz_txn_begin/commit/abort` — Transactions
- `pgz_get/put/delete` — Key-value operations
- `pgz_scan/iter_next/iter_close` — Range scans
- `pgz_free` — Memory management

### Suggested Implementation Order

**Zig (Storage Engine):**
1. `types.zig`, `crc32c.zig` — Pure, no dependencies
2. `io.zig` — Foundation for all disk access
3. `vlog.zig` — Simple append-only log
4. `sstable.zig` — Sorted key blocks
5. `manifest.zig` — Database metadata
6. `lsm.zig` — Ties it together
7. `txn.zig` — MVCC layer
8. `db.zig` — User-facing API
9. `capi.zig` — C API for Go FFI

**Go (Server) — after M2:**
10. `pkg/storage` — Go bindings (done)
11. `pkg/pgwire` — PostgreSQL wire protocol
12. `pkg/parser` — SQL parsing
13. `pkg/planner` — Query planning

---

## 13. Falsifiable Hypotheses (With Tests)

These are **bets we're making** that could be wrong. Each has a test to prove/disprove it:

### H1: Key-Value Separation Reduces WAF

**Claim:** KV-separation reduces host WAF to ≤3× for median value size ≥ 512 bytes.

**Test:**
- Synthetic workload varying value size (64B, 256B, 512B, 1KB, 4KB, 16KB)
- Measure WAF for our design vs "values-in-LSM" baseline
- If WAF improvement < 20% for 512B+ values, hypothesis is false

**Why this might be wrong:** Small values + vLog overhead might negate benefits.

---

### H2: Compaction Governor Bounds Tail Latency

**Claim:** Compaction governor holds p99 read latency within 2× of p50 under 0.7× device saturation.

**Test:**
- Steady mixed read/write workload
- Sweep compaction budget from 10% to 100%
- Measure p50 and p99 read latency
- Assert: p99 ≤ 2× p50 when budget correctly tuned

**Why this might be wrong:** I/O contention might cause spikes regardless of budgeting.

---

### H3: Group Commit Keeps Latency Low

**Claim:** Group-commit window ≤ 2 ms keeps commit p99 ≤ 5 ms on consumer NVMe (macOS).

**Test:**
- Microbenchmark: vary group-commit window (0.5ms, 1ms, 2ms, 5ms, 10ms)
- Measure commit p50/p99 on your Mac's SSD
- Assert: 2ms window → p99 ≤ 5ms

**Why this might be wrong:** macOS `F_FULLFSYNC` is slower than Linux `fdatasync`; consumer SSDs vary widely.

> **Note:** On Linux with PLP NVMe, we'd expect tighter latency (p99 ≤ 3ms). Test both once Linux support is added.

---

## 14. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Tail spikes from compaction/GC** | Users see random slowdowns | Strict token-bucket budgets; admission control; pause background work on p99 breach |
| **High WAF** | SSD wear; performance degradation | Enable KV-GC; use larger table blocks; revisit level fan-out; consider ZNS |
| **macOS I/O limitations** | No io_uring, weaker async | Abstract I/O layer early; kqueue + thread pool works; add io_uring for Linux later |
| **Scope creep (planner/joins)** | Never ship | Hard rule: defer until M3 exits |

---

## 15. Agent/LLM Collaboration (Safe Delegation)

These tasks are safe to delegate to AI assistants:

| Task | Why Safe | Guardrails |
|------|----------|------------|
| **Generate pure components + tests** | Deterministic, testable | crc32c, fence-index encode/decode, bloom filters |
| **Scaffold I/O wrappers** | Well-defined interface | io.zig with alignment asserts and short-I/O loops |
| **Implement vlog.zig** | Property testable | Tests for padding, CRC, crash truncation |
| **Bench harness** | Read-only, observable | Queue-depth vs latency histograms |
| **PG wire shim** | Protocol is well-specified | Handshake, simple query, row framing; sqllogictest runner |

**Guardrails:**
- Agents **NEVER** change on-disk formats without approved RFC
- Agents **NEVER** change durability semantics without approved RFC
- All generated code requires human review before merge

---

## 16. Open Decisions (Time-Boxed)

These decisions are **deferred** until we have data:

### Inlining Small Values

**Question:** Should we inline values ≤ N bytes directly into LSM keys (avoiding vLog read for point lookups)?

**Trade-offs:**
- Pro: Faster point reads for small values
- Con: Larger keys = more compaction work

**Decision point:** After M1, measure point-read latency distribution by value size.

---

### Compression Policy

**Tentative:**
- L0/L1: LZ4 (fast, moderate compression)
- L2+: Zstd (slower, better compression)

**Open question:** Does CPU budget allow Zstd at L2+? Profile on target hardware.

---

### Commit Ordering

**Options:**
1. **Strict**: `fdatasync` both vLog + commit log before acknowledging
2. **Relaxed**: Use FUA (Force Unit Access) hints; trust PLP

**Trade-offs:**
- Strict: Works on any hardware; higher latency
- Relaxed: Faster; requires PLP NVMe (power loss protection)

**Decision point:** After M0, test on target hardware.

---

## Glossary

| Term | Definition |
|------|------------|
| **WAF** | Write Amplification Factor — ratio of bytes written to device vs bytes written by application |
| **LSM** | Log-Structured Merge Tree — write-optimized data structure |
| **vLog** | Value Log — append-only file storing row values |
| **vptr** | Value Pointer — (segment, offset, length) reference to vLog |
| **SSTable** | Sorted String Table — immutable file of sorted key-value entries |
| **MVCC** | Multi-Version Concurrency Control — keep multiple versions for concurrent access |
| **SI** | Snapshot Isolation — transaction sees consistent snapshot as of start time |
| **HLC** | Hybrid Logical Clock — combines wall time with logical counter |
| **FPR** | False Positive Rate — bloom filter error rate |
| **QD** | Queue Depth — number of in-flight I/O requests |
| **p99** | 99th percentile latency — slowest 1% of requests |
| **PLP** | Power Loss Protection — capacitor-backed NVMe for crash safety |
| **FUA** | Force Unit Access — write directly to media, bypass drive cache |
| **ZNS** | Zoned Namespace — SSD interface with sequential-write zones |
| **O_DIRECT** | Linux flag to bypass kernel page cache |
| **F_NOCACHE** | macOS equivalent of O_DIRECT (cache bypass hint) |
| **F_FULLFSYNC** | macOS: force write to physical media (stronger than fsync) |
| **io_uring** | Linux async I/O interface (kernel 5.1+) |
| **kqueue** | macOS/BSD event notification system (used for async I/O) |

---

## Further Reading

- [WiscKey: Separating Keys from Values in SSD-conscious Storage](https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf) — Key-value separation paper
- [The Log-Structured Merge-Tree (O'Neil et al.)](http://www.cs.umb.edu/~pon} poneil/lsmtree.pdf) — Original LSM paper
- [RocksDB Wiki](https://github.com/facebook/rocksdb/wiki) — Production LSM implementation
- [What Every Programmer Should Know About Memory](https://people.freebsd.org/~lstewart/articles/cpumemory.pdf) — Deep dive on memory hierarchy
- [Modern SSD Internals](https://codecapsule.com/2014/02/12/coding-for-ssds-part-1-introduction-and-table-of-contents/) — SSD architecture series
- [Jepsen: Consistency Models](https://jepsen.io/consistency) — Understanding isolation levels
