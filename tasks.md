# SSD-First Storage Engine — Implementation Tasks

> Organized by milestones from `plan.md`. Each milestone has exit criteria that must pass before moving on.

---

## Pre-M0: Project Setup

### Development Environment
- [x] Initialize Zig project structure
- [x] Set up build.zig with module organization
- [x] Configure test runner
- [ ] Set up CI (GitHub Actions for macOS)
- [x] Add formatting/linting (zig fmt)

### Module Skeleton
Create empty files with basic structure:
- [x] `src/types.zig` — Constants, error types, IDs
- [x] `src/crc32c.zig` — Checksum placeholder
- [x] `src/io.zig` — I/O abstraction interface
- [x] `src/vlog.zig` — Value log placeholder
- [x] `src/sstable.zig` — SSTable placeholder
- [x] `src/manifest.zig` — Manifest placeholder
- [x] `src/lsm.zig` — LSM placeholder
- [x] `src/txn.zig` — Transaction placeholder
- [x] `src/db.zig` — High-level API placeholder

### Testing Infrastructure
- [x] Create test utilities (temp directories, cleanup)
- [x] Add assertion helpers for common checks
- [x] Set up benchmark harness (timing, throughput measurement)
- [x] Add fault injection framework (for crash testing later)

---

## M0: Storage Skeleton (macOS, Zig)

**Goal:** Crash-safe append-only storage with basic CLI.

### types.zig — Foundation Types
- [x] Define `PageSize = 4096` constant
- [x] Define `SegmentId`, `Offset`, `Length` types
- [x] Define `ValuePointer` struct: `{ segment: u32, offset: u64, len: u32 }`
- [ ] Define error types: `StorageError`, `CorruptionError`, `IOError`
- [x] Define `Epoch` type for versioning
- [x] Add alignment helpers: `alignUp(n, alignment)`, `isAligned(n, alignment)`

### crc32c.zig — Checksums
- [x] Implement CRC32C algorithm (Castagnoli polynomial)
- [ ] Hardware acceleration check (use `@ctz` intrinsics if available)
- [x] Fallback software implementation
- [x] Add `crc32c(data: []const u8) -> u32`
- [ ] Add `crc32cUpdate(crc: u32, data: []const u8) -> u32` for streaming
- [x] Write tests: known vectors, empty input, large input

### io.zig — Platform I/O Abstraction (macOS First)

#### Common Interface
- [x] Define `IOOp` union: `{ read, write, fsync }`
- [x] Define `Completion` struct: `{ op, result, userdata }`
- [ ] Define `AsyncIO` interface:
  ```zig
  pub const AsyncIO = struct {
      pub fn submit(self: *AsyncIO, op: IOOp) !void
      pub fn poll(self: *AsyncIO, completions: []Completion) !usize
      pub fn submitAndWait(self: *AsyncIO, op: IOOp) !void // blocking
  };
  ```

#### macOS Backend
- [ ] Implement file open with `F_NOCACHE` via `fcntl()`
- [ ] Implement aligned buffer allocation (`std.heap.page_allocator`)
- [ ] Implement synchronous `pread`/`pwrite` (first pass, simplest)
- [ ] Implement `F_FULLFSYNC` for true durability
- [ ] Implement `F_PREALLOCATE` for space reservation
- [ ] Add alignment assertions (panic on unaligned I/O)
- [ ] Write tests: basic read/write, alignment enforcement

#### Fallback/Test Backend
- [ ] Implement synchronous backend using standard file I/O
- [ ] Add I/O tracing (log all operations for debugging)
- [ ] Add artificial delay injection (for latency testing)

### vlog.zig — Value Log (Append-Only)

#### Record Format
```
┌──────────┬───────────┬─────────────────┬────────────────────┐
│ len: u32 │ crc32c: u32 │ payload: bytes │ zero-pad → 4KiB  │
└──────────┴───────────┴─────────────────┴────────────────────┘
```

#### Writer
- [ ] Define `VLogWriter` struct
- [ ] Implement `append(payload: []const u8) -> ValuePointer`
  - [ ] Calculate padded size (round up to 4KiB)
  - [ ] Write header (len, crc32c)
  - [ ] Write payload
  - [ ] Write zero padding
  - [ ] Return value pointer
- [ ] Implement `sync()` — flush to disk
- [ ] Track current segment and offset
- [ ] Handle segment rotation (when segment reaches max size)

#### Reader
- [ ] Define `VLogReader` struct
- [ ] Implement `read(vptr: ValuePointer) -> []const u8`
  - [ ] Seek to offset
  - [ ] Read header
  - [ ] Verify CRC32C
  - [ ] Return payload (without padding)
- [ ] Handle read errors (corruption, EOF)

#### Recovery
- [ ] Implement `scanLastGood(segment_path) -> last_valid_offset`
  - [ ] Scan from beginning
  - [ ] Validate each record (CRC check)
  - [ ] Return offset of last valid record
  - [ ] Truncate file to last valid offset on recovery
- [ ] Write crash recovery tests:
  - [ ] Partial write (truncated mid-record)
  - [ ] Corrupted CRC
  - [ ] Valid file

#### Tests
- [ ] Write + read round-trip
- [ ] Multiple records
- [ ] Large payloads (> 4KiB, spanning multiple pages)
- [ ] Recovery from partial write
- [ ] Recovery from corruption

### sstable.zig — Single SSTable Run (No Levels Yet)

#### Block Format
```
┌──────────────┬───────────┬────────────────────┬───────────┬────────────┐
│ block_len: u32 │ count: u32 │ entries...       │ crc32c: u32 │ pad→4KiB │
└──────────────┴───────────┴────────────────────┴───────────┴────────────┘

Entry: [k_len: u16 | key | vptr (seg: u32, off: u64, len: u32) | epoch: u32]
```

#### Writer
- [ ] Define `SSTableBuilder` struct
- [ ] Implement `add(key: []const u8, vptr: ValuePointer, epoch: u32)`
  - [ ] Accumulate entries in current block
  - [ ] Flush block when size threshold reached (32-64 KiB)
- [ ] Implement block flushing:
  - [ ] Encode entries
  - [ ] Calculate CRC32C
  - [ ] Pad to 4KiB alignment
  - [ ] Write to file
  - [ ] Record (first_key, file_offset) in fence index
- [ ] Implement `finish() -> SSTableMetadata`
  - [ ] Flush final block
  - [ ] Write fence index page
  - [ ] Write footer with metadata
- [ ] Write tests: empty table, single entry, many entries

#### Fence Index
```
┌─────────────────────────────────────────────────┬───────────┐
│ sorted array of (first_key_of_block, file_off) │ crc32c    │
└─────────────────────────────────────────────────┴───────────┘
```
- [ ] Implement fence index encoding
- [ ] Implement fence index decoding
- [ ] Implement binary search on fence index

#### Reader
- [ ] Define `SSTableReader` struct
- [ ] Implement `open(path) -> SSTableReader`
  - [ ] Read footer
  - [ ] Read and parse fence index
  - [ ] Cache fence index in memory
- [ ] Implement `get(key: []const u8) -> ?ValuePointer`
  - [ ] Binary search fence index to find block
  - [ ] Read block
  - [ ] Verify CRC
  - [ ] Linear search within block
  - [ ] Return vptr if found
- [ ] Implement `iterator() -> SSTableIterator`
- [ ] Write tests: point lookup, iteration, not found

### manifest.zig — Superblock & Manifest

#### Superblock Format (two copies for atomicity)
- [ ] Define superblock structure:
  - [ ] Magic number
  - [ ] Version
  - [ ] Pointer to active manifest
  - [ ] vLog epoch
  - [ ] CRC32C
- [ ] Implement superblock write (to inactive copy)
- [ ] Implement superblock read (pick valid copy)
- [ ] Implement atomic swap (write → fsync → update pointer)

#### Manifest
- [ ] Define manifest entry types:
  - [ ] `AddSegment { segment_id, path }`
  - [ ] `RemoveSegment { segment_id }`
  - [ ] `AddSSTable { level, path, first_key, last_key }`
  - [ ] `RemoveSSTable { level, path }`
  - [ ] `VLogEpoch { epoch }`
- [ ] Implement append-only manifest log
- [ ] Implement manifest read (replay to reconstruct state)
- [ ] Implement manifest checkpoint (compact to single state)

#### Recovery
- [ ] Implement full recovery sequence:
  1. Read superblock (pick valid copy)
  2. Read manifest
  3. Verify vLog segments exist
  4. Scan vLog for last good offset
  5. Rebuild in-memory state
- [ ] Write crash recovery tests

### commit_log.zig — Commit Log (Group Commit)

#### Commit Record Format
```
┌───────────┬───────────────┬────────────────┬──────────────┬───────────┐
│ txid: u64 │ commit_ts: u64 │ ptr_count: u32 │ vptrs...     │ crc32c    │
└───────────┴───────────────┴────────────────┴──────────────┴───────────┘
```

- [ ] Implement commit record encoding/decoding
- [ ] Implement commit log writer with group commit:
  - [ ] Buffer pending commits
  - [ ] Flush batch on threshold (time or count)
  - [ ] Single `F_FULLFSYNC` for batch
- [ ] Implement commit log reader
- [ ] Implement commit log recovery (replay committed txns)

### db.zig — High-Level API (M0 Scope)

- [ ] Define `DB` struct holding vlog, sstable, manifest
- [ ] Implement `DB.open(path) -> DB`
- [ ] Implement `DB.put(key, value) -> ValuePointer`
- [ ] Implement `DB.get(key) -> ?[]const u8`
- [ ] Implement `DB.flush()` — force MemTable to SSTable
- [ ] Implement `DB.close()`

### CLI (Basic)
- [ ] Parse command-line arguments
- [ ] Implement `put <key> <value>` command
- [ ] Implement `get <key>` command
- [ ] Implement `flush` command
- [ ] Implement `scan` command (iterate all keys)

### M0 Exit Criteria Verification
- [ ] **Test: Crash-safe** — Fault injection tests pass
- [ ] **Test: 4 KiB-aligned I/O only** — Assertions in io.zig, no test failures
- [ ] **Test: Sequential write pattern** — I/O trace shows no random writes
- [ ] **Test: CLI works** — `put`, `get`, `flush` integration tests pass

---

## M1: LSM + GC + Governor

**Goal:** Full LSM with compaction, vLog GC, and I/O throttling.

### MemTable (In-Memory Buffer)

- [ ] Define `MemTable` interface
- [ ] Implement skip list data structure:
  - [ ] Node structure with forward pointers
  - [ ] Random level generation
  - [ ] Insert operation
  - [ ] Search operation
  - [ ] Iteration (in-order)
- [ ] Add size tracking (bytes used)
- [ ] Implement freeze (make immutable for flush)
- [ ] Implement snapshot for consistent reads
- [ ] Write tests: insert, search, iterate, concurrent access

### LSM Tree Structure

- [ ] Define level structure: L0 (tiered), L1 (tiered), L2+ (leveled)
- [ ] Track SSTables per level
- [ ] Implement level size limits:
  - [ ] L0: 4 files trigger flush
  - [ ] L1: 64 MB
  - [ ] L2: 640 MB
  - [ ] L3+: 10× previous level
- [ ] Implement SSTable metadata tracking (key range, size, level)

### Write Path (Full)

- [ ] Implement `put` with MemTable:
  1. Write to commit log (group commit)
  2. Insert into MemTable
  3. Check MemTable size threshold
  4. If full: freeze MemTable, create new one, trigger flush
- [ ] Implement MemTable flush to L0 SSTable
- [ ] Update manifest on flush
- [ ] Handle concurrent writes (mutex or lock-free)

### Read Path (Full)

- [ ] Implement `get` with LSM merge:
  1. Check MemTable
  2. Check frozen MemTables (if any)
  3. Check L0 SSTables (all, newest first — may overlap)
  4. Check L1+ SSTables (binary search — non-overlapping)
  5. Fetch value from vLog using vptr
- [ ] Implement `scan` with merge iterator:
  - [ ] Heap-based merge of all sources
  - [ ] Handle duplicates (newest wins)
  - [ ] Handle tombstones (skip deleted)

### Bloom Filters

- [ ] Implement Bloom filter:
  - [ ] Bit array
  - [ ] Multiple hash functions (use MurmurHash or xxHash)
  - [ ] Insert key
  - [ ] Query key (probably in set?)
- [ ] Configure FPR ≈ 0.1% (tune bits per key)
- [ ] Build Bloom filter during SSTable creation
- [ ] Store Bloom filter in SSTable (separate block or footer)
- [ ] Check Bloom filter before reading SSTable in `get`
- [ ] Write tests: false positive rate measurement

### Compaction — Tiered (L0/L1)

- [ ] Implement L0 → L1 compaction trigger (file count threshold)
- [ ] Implement tiered merge:
  - [ ] Select all L0 files
  - [ ] Merge-sort into L1 files
  - [ ] Split output by size (64 MB target)
- [ ] Update manifest atomically
- [ ] Delete old SSTables after manifest update

### Compaction — Leveled (L2+)

- [ ] Implement level size trigger
- [ ] Implement SSTable selection:
  - [ ] Pick oldest SSTable in level
  - [ ] Find overlapping SSTables in next level
- [ ] Implement leveled merge:
  - [ ] Merge selected SSTables
  - [ ] Output non-overlapping SSTables to next level
- [ ] Handle key range splitting
- [ ] Update manifest atomically
- [ ] Delete obsolete SSTables

### Compaction Governor (Token Bucket)

- [ ] Implement token bucket rate limiter:
  - [ ] Tokens refill at fixed rate
  - [ ] I/O operations consume tokens
  - [ ] Block if no tokens available
- [ ] Configure separate buckets for:
  - [ ] Compaction I/O
  - [ ] Compaction CPU
- [ ] Implement adaptive throttling:
  - [ ] Monitor p95/p99 read latency
  - [ ] Reduce compaction budget when latency rises
  - [ ] Increase budget when latency drops
- [ ] Add compaction metrics (bytes written, time spent)

### vLog Garbage Collection

- [ ] Track vLog segment usage:
  - [ ] Count live bytes per segment
  - [ ] Update during compaction (when vptrs change)
- [ ] Implement GC trigger:
  - [ ] Space trigger: segment < 50% live
  - [ ] Age trigger: segment older than threshold
- [ ] Implement GC process:
  1. Select candidate segment
  2. Scan LSM for live vptrs pointing to segment
  3. Copy live values to new segment
  4. Update vptrs in LSM (via remap table)
  5. Delete old segment
- [ ] Implement remap table (old vptr → new vptr)
- [ ] Handle concurrent reads during GC

### Background Workers

- [ ] Implement background thread pool
- [ ] Implement flush worker (MemTable → SSTable)
- [ ] Implement compaction worker
- [ ] Implement GC worker
- [ ] Add graceful shutdown (drain queues)

### M1 Exit Criteria Verification
- [ ] **Benchmark: Ingest ≥ 100 MB/s** — Sustained write benchmark
- [ ] **Benchmark: Host WAF ≤ 4×** — Measure bytes written to device / bytes from app
- [ ] **Benchmark: p99 read stable during compaction** — No 10× latency spikes

---

## M2: MVCC (Snapshot Isolation) + Correctness

**Goal:** Transaction support with snapshot isolation, verified correct.

### Transaction Manager

- [ ] Define `TransactionId` (u64)
- [ ] Define `Timestamp` (u64, monotonic)
- [ ] Implement transaction ID allocator (atomic counter)
- [ ] Implement timestamp allocator (HLC or monotonic clock)
- [ ] Track active transactions
- [ ] Track committed transactions (with commit timestamps)

### Snapshot Management

- [ ] Define `Snapshot` struct:
  - [ ] `read_ts`: timestamp when snapshot was taken
  - [ ] `active_txns`: list of in-progress transaction IDs
- [ ] Implement `beginTransaction() -> Snapshot`
- [ ] Implement `commitTransaction(txn_id, writes) -> commit_ts`
- [ ] Implement `abortTransaction(txn_id)`

### MVCC in LSM

- [ ] Extend SSTable entry to include `commit_ts`:
  ```
  Entry: [k_len | key | commit_ts | vptr | is_tombstone]
  ```
- [ ] Store multiple versions per key
- [ ] Sort by (key, commit_ts DESC) in SSTable

### Visibility Check

- [ ] Implement visibility rule:
  ```
  visible(version, snapshot) =
    version.commit_ts <= snapshot.read_ts AND
    version.commit_ts NOT IN snapshot.active_txns AND
    (no newer version visible OR version is tombstone)
  ```
- [ ] Integrate visibility into `get`:
  - [ ] Scan versions from newest to oldest
  - [ ] Return first visible version
  - [ ] Return null if tombstone is visible
- [ ] Integrate visibility into `scan`:
  - [ ] Filter invisible versions
  - [ ] Skip tombstoned keys

### Write-Write Conflict Detection

- [ ] Track write set per transaction
- [ ] On commit, check for conflicts:
  - [ ] Any key written by another committed txn since our snapshot?
  - [ ] If yes, abort with conflict error
- [ ] Implement optimistic concurrency control

### Tombstones

- [ ] Implement delete as tombstone write
- [ ] Propagate tombstones through compaction
- [ ] Expire tombstones when no snapshot can see the deleted version

### Garbage Collection (MVCC-Aware)

- [ ] Track `global_safe_ts` = min(all active snapshot read_ts)
- [ ] During compaction:
  - [ ] Drop versions where `commit_ts < global_safe_ts` AND newer version exists
  - [ ] Keep tombstones until no snapshot can see deleted version
- [ ] During vLog GC:
  - [ ] Only collect values not referenced by any visible version

### Recovery Invariants

- [ ] On recovery, rebuild active transaction state
- [ ] Abort any in-progress transactions (not in commit log)
- [ ] Verify committed transactions have durable values

### Correctness Testing

- [ ] Integrate SQLLogicTest runner (subset of tests)
- [ ] Integrate Elle (Jepsen's checker):
  - [ ] Generate transaction histories
  - [ ] Check for SI anomalies (write cycles, etc.)
  - [ ] Assert no anomalies found
- [ ] Write targeted tests:
  - [ ] Read-your-own-writes
  - [ ] Snapshot sees consistent state
  - [ ] Write-write conflict detection
  - [ ] Tombstone visibility

### M2 Exit Criteria Verification
- [ ] **Test: SQLLogicTest subset green**
- [ ] **Test: Elle shows no SI anomalies**
- [ ] **Test: Crash recovery tests pass**

---

## M3: PostgreSQL Wire Protocol + Minimal SQL

**Goal:** `psql` can connect and run basic queries.

### TCP Server

- [ ] Implement TCP listener (port 5432 default)
- [ ] Accept connections
- [ ] Spawn connection handler per client
- [ ] Implement connection timeout
- [ ] Implement graceful shutdown

### Protocol Message Framing

- [ ] Implement message reading:
  - [ ] Read message type (1 byte) — except startup
  - [ ] Read message length (4 bytes, big-endian)
  - [ ] Read payload
- [ ] Implement message writing:
  - [ ] Write type + length + payload

### Startup Flow

- [ ] Parse StartupMessage:
  - [ ] Protocol version (3.0 = 196608)
  - [ ] Parameters (user, database, etc.)
- [ ] Send AuthenticationOk (for now, no auth)
- [ ] Send ParameterStatus messages (server_version, etc.)
- [ ] Send BackendKeyData (process ID, secret key)
- [ ] Send ReadyForQuery ('I' for idle)

### Authentication (Basic)

- [ ] Implement AuthenticationCleartextPassword
- [ ] Implement password verification (hardcoded or file-based)
- [ ] Plan for MD5/SCRAM later

### Simple Query Protocol

- [ ] Receive Query message (SQL string)
- [ ] Parse SQL (see below)
- [ ] Execute query
- [ ] Send RowDescription (column metadata)
- [ ] Send DataRow (for each row)
- [ ] Send CommandComplete (e.g., "SELECT 3")
- [ ] Send ReadyForQuery

### SQL Parser

- [ ] Evaluate options:
  - [ ] Hand-written recursive descent (simple subset)
  - [ ] pg_query C bindings (full Postgres parser)
- [ ] Implement/integrate parser for:
  - [ ] `CREATE TABLE name (col type, ...)`
  - [ ] `INSERT INTO table (cols) VALUES (...)`
  - [ ] `SELECT cols FROM table WHERE ...`
  - [ ] `BEGIN`
  - [ ] `COMMIT`
  - [ ] `ROLLBACK`
- [ ] Generate AST for each statement type

### Schema & Catalog

- [ ] Define `TableDef` struct (name, columns, primary key)
- [ ] Define `ColumnDef` struct (name, type, nullable)
- [ ] Implement supported types:
  - [ ] `INTEGER` / `BIGINT`
  - [ ] `TEXT` / `VARCHAR(n)`
  - [ ] `BOOLEAN`
  - [ ] `TIMESTAMP`
- [ ] Store schemas in LSM (system namespace)
- [ ] Implement `CREATE TABLE` executor
- [ ] Implement schema lookup by table name

### Tuple Encoding

- [ ] Define tuple format:
  - [ ] Null bitmap
  - [ ] Fixed-size columns (inline)
  - [ ] Variable-size columns (length-prefixed)
- [ ] Implement `encodeTuple(schema, values) -> []u8`
- [ ] Implement `decodeTuple(schema, bytes) -> []Value`

### Query Execution

- [ ] Implement `INSERT` executor:
  - [ ] Parse values
  - [ ] Encode tuple
  - [ ] Put to storage engine (within transaction)
- [ ] Implement `SELECT` executor:
  - [ ] Open table scan
  - [ ] Apply WHERE filter (basic: `col = value`, `col > value`)
  - [ ] Project columns
  - [ ] Return rows
- [ ] Implement `BEGIN` / `COMMIT` / `ROLLBACK`
- [ ] Implement primary key lookup optimization

### Result Formatting

- [ ] Implement text format for each type:
  - [ ] Integer → string
  - [ ] Text → as-is
  - [ ] Boolean → "t" / "f"
  - [ ] Timestamp → ISO 8601
  - [ ] NULL → null indicator
- [ ] Build RowDescription from schema
- [ ] Build DataRow from tuple

### Error Handling

- [ ] Implement ErrorResponse message:
  - [ ] Severity (ERROR, FATAL, etc.)
  - [ ] Code (SQLSTATE)
  - [ ] Message
- [ ] Map internal errors to SQLSTATE codes
- [ ] Send error and remain ready for next query

### M3 Exit Criteria Verification
- [ ] **Test: `psql` connects and works**
  - [ ] Connect with `psql -h localhost`
  - [ ] Run `CREATE TABLE`
  - [ ] Run `INSERT`
  - [ ] Run `SELECT`
- [ ] **Test: SQLLogicTest subset over wire protocol**
- [ ] **Benchmark: YCSB A/C/F adapters run**
  - [ ] Implement YCSB-compatible schema
  - [ ] Run workload A (50% read, 50% update)
  - [ ] Run workload C (100% read)
  - [ ] Run workload F (50% read, 50% read-modify-write)

---

## M4: Observability + QoS Polish

**Goal:** Metrics, histograms, SLO-aware tuning.

### Metrics Collection

- [ ] Implement metrics registry
- [ ] Add counters:
  - [ ] `storage_puts_total`
  - [ ] `storage_gets_total`
  - [ ] `storage_scans_total`
  - [ ] `compaction_runs_total`
  - [ ] `gc_runs_total`
- [ ] Add gauges:
  - [ ] `memtable_size_bytes`
  - [ ] `level_size_bytes{level}`
  - [ ] `vlog_live_bytes`
  - [ ] `vlog_garbage_bytes`
  - [ ] `active_transactions`

### Latency Histograms

- [ ] Implement HDR histogram (or similar):
  - [ ] Configurable precision
  - [ ] Efficient percentile queries
- [ ] Track latency distributions:
  - [ ] `get_latency_seconds`
  - [ ] `put_latency_seconds`
  - [ ] `commit_latency_seconds`
  - [ ] `compaction_duration_seconds`
- [ ] Expose p50, p95, p99, p999

### Write Amplification Tracking

- [ ] Track `bytes_written_by_app`
- [ ] Track `bytes_written_to_device`
- [ ] Calculate and expose `host_waf = device / app`
- [ ] Track per-component: vLog, SSTable, commit log

### Queue Depth Monitoring

- [ ] Track current I/O queue depth
- [ ] Track max queue depth
- [ ] Alert/log when approaching saturation

### Metrics Export

- [ ] Implement Prometheus exposition format endpoint
- [ ] Implement JSON metrics endpoint
- [ ] Add `/metrics` HTTP handler (simple HTTP server)

### SLO-Aware Compaction

- [ ] Define SLO thresholds (e.g., p99 < 5ms)
- [ ] Implement SLO monitor:
  - [ ] Check p99 every N seconds
  - [ ] Compare to threshold
- [ ] Implement adaptive response:
  - [ ] p99 > threshold: reduce compaction budget 50%
  - [ ] p99 < threshold * 0.5: increase compaction budget
- [ ] Add hysteresis to prevent oscillation

### Admin Commands

- [ ] Implement `SHOW METRICS` SQL command
- [ ] Implement `SHOW WAF` command
- [ ] Implement `VACUUM` command (trigger GC)
- [ ] Implement `COMPACT` command (trigger compaction)

### Logging

- [ ] Implement structured logging
- [ ] Add log levels (DEBUG, INFO, WARN, ERROR)
- [ ] Log significant events:
  - [ ] Compaction start/end
  - [ ] GC start/end
  - [ ] SLO violations
  - [ ] Recovery events

### M4 Exit Criteria Verification
- [ ] **Test: Tail latency bounded under sustained background work**
  - [ ] Run write workload + read workload concurrently
  - [ ] Measure p99 during compaction
  - [ ] Assert p99 stays within SLO
- [ ] **Test: Operators can monitor system health**
  - [ ] Metrics endpoint returns data
  - [ ] Histograms show reasonable values

---

## M5: ZNS Backend (Optional)

**Goal:** Exploit Zoned Namespace SSDs for lower WAF and tighter tail latency.

### ZNS Understanding
- [ ] Research ZNS concepts:
  - [ ] Zones and zone states
  - [ ] Sequential write requirement
  - [ ] Zone capacity vs size
  - [ ] Zone reset
- [ ] Identify ZNS device for testing (or use emulation)

### Zone Management
- [ ] Implement zone discovery (list zones, capacities)
- [ ] Implement zone state tracking (empty, open, full, etc.)
- [ ] Implement zone allocation strategy
- [ ] Map LSM levels to zones:
  - [ ] L0/L1: hot zones (frequently reset)
  - [ ] L2+: cold zones (infrequent rewrite)

### Sequential Write Enforcement
- [ ] Ensure all writes within zone are sequential
- [ ] Buffer writes to maintain sequentiality
- [ ] Handle zone wrap-around

### GC via Zone Reset
- [ ] Replace copy-based GC with zone reset
- [ ] Track zone liveness
- [ ] Implement zone selection for reset (least live data)
- [ ] Coordinate with compaction

### M5 Exit Criteria Verification
- [ ] **Benchmark: Lower device-level WAF vs block backend**
- [ ] **Benchmark: Tighter p99 under compaction**

---

## Ongoing: Cross-Cutting Concerns

### Linux Backend (Post-M0)
- [ ] Implement io_uring backend:
  - [ ] Initialize io_uring instance
  - [ ] Submit read/write SQEs
  - [ ] Harvest CQEs
  - [ ] Handle errors
- [ ] Implement O_DIRECT support
- [ ] Implement `fdatasync` / `fsync`
- [ ] Benchmark io_uring vs macOS kqueue

### Windows Backend (Future)
- [ ] Research IOCP (I/O Completion Ports)
- [ ] Implement Windows I/O backend
- [ ] Handle unbuffered I/O

### Testing Throughout
- [ ] Unit tests for each module
- [ ] Integration tests for each milestone
- [ ] Crash/recovery tests (fault injection)
- [ ] Performance regression tests
- [ ] Cross-platform CI (macOS now, Linux later)

### Documentation Throughout
- [ ] API documentation (doc comments)
- [ ] Architecture documentation (how it works)
- [ ] Operations guide (how to run, configure, monitor)

---

## Hypothesis Validation Tasks

These are experiments to validate or invalidate our design bets:

### H1: KV-Separation Reduces WAF
- [ ] Implement "values-in-LSM" mode (feature flag)
- [ ] Run synthetic workload varying value size
- [ ] Measure WAF for both modes
- [ ] Produce comparison report
- [ ] **Expected:** WAF ≤ 3× for values ≥ 512B with KV-separation

### H2: Compaction Governor Bounds Tail
- [ ] Run sustained mixed workload at 0.7× device saturation
- [ ] Sweep compaction budget (10%, 25%, 50%, 75%, 100%)
- [ ] Measure p50 and p99 for each
- [ ] Produce latency vs budget chart
- [ ] **Expected:** Correctly tuned budget → p99 ≤ 2× p50

### H3: Group Commit Latency
- [ ] Implement configurable group commit window
- [ ] Microbenchmark commit latency vs window size
- [ ] Test on macOS consumer SSD
- [ ] Produce window size vs p99 chart
- [ ] **Expected:** 2ms window → p99 ≤ 5ms on macOS

---

## Priority Order

### Critical Path (M0-M3)
These must be completed in order:

1. **Pre-M0**: Project setup, module skeletons
2. **M0**: vLog, SSTable, manifest, basic DB API
3. **M1**: Full LSM, compaction, GC, throttling
4. **M2**: MVCC, transactions, correctness tests
5. **M3**: Wire protocol, SQL, `psql` works

### High Priority (M4)
After M3:
- Observability and metrics
- SLO-aware tuning
- Admin tooling

### Optional (M5)
If you have ZNS hardware:
- ZNS backend for reduced WAF

### Parallel Work
Can be done alongside milestones:
- Linux io_uring backend (after M0 macOS works)
- Documentation
- Performance benchmarking
- Hypothesis validation experiments
