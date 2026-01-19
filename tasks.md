# pgz — Implementation Tasks (Zig Storage Engine + Go Server)

> Organized by milestones from `plan.md`. Each milestone has exit criteria that must pass before moving on.
>
> **Architecture:**
> - **Zig storage engine** (`/src`, `/include`): LSM, vLog, I/O, transactions, checksums, recovery, `capi.zig` exports C ABI
> - **Go server** (`/server`): PostgreSQL wire protocol (v3), SQL parser, query planner/executor
> - **Boundary:** Go calls Zig via **cgo** bindings in `server/pkg/storage/`

---

## Module Map (source of truth)

### Zig Storage Engine (`/src`, `/include`)

| File | Purpose |
|------|---------|
| `src/types.zig` | Constants, IDs, errors, helpers |
| `src/crc32c.zig` | Checksums |
| `src/io.zig` | Platform I/O abstraction (macOS first; Linux later) |
| `src/vlog.zig` | Value log (append/read/recovery) |
| `src/sstable.zig` | SSTable writer/reader (blocks, fence index, bloom) |
| `src/manifest.zig` | Superblock + manifest log + recovery |
| `src/commit_log.zig` | Durability records / group commit |
| `src/lsm.zig` | Memtable, flush, compaction, levels |
| `src/txn.zig` | MVCC / snapshot isolation, tx lifecycle |
| `src/db.zig` | High-level DB API: open/close/get/put/delete/scan/txn |
| `src/capi.zig` | C ABI exports for Go FFI |
| `include/pgz.h` | C header consumed by cgo |

### Go Server (`/server`)

| Path | Purpose |
|------|---------|
| `server/cmd/pgz-server/` | Server entry point |
| `server/pkg/storage/` | Go bindings to Zig via cgo |
| `server/pkg/pgwire/` | PostgreSQL v3 protocol (M3) |
| `server/pkg/parser/` | SQL parser (M3) |
| `server/pkg/planner/` | Planner/executor + catalog (M3) |

---

## Pre-M0: Project Setup / Scaffolding

### Tooling / Build Orchestration
- [x] `justfile` with: `just test`, `just build`, `just run`, `just fmt`
- [ ] CI (GitHub Actions):
  - [ ] macOS: build Zig lib + Go server, run tests
  - [ ] Linux (optional early): Zig + Go tests

### Module Skeleton
Zig engine:
- [x] `src/types.zig`
- [x] `src/crc32c.zig`
- [x] `src/io.zig`
- [x] `src/vlog.zig`
- [x] `src/sstable.zig`
- [x] `src/manifest.zig`
- [x] `src/lsm.zig`
- [x] `src/txn.zig`
- [x] `src/db.zig`
- [x] `src/capi.zig`
- [x] `include/pgz.h`

Go server:
- [x] `server/pkg/storage/` (cgo bindings)
- [x] `server/cmd/pgz-server/main.go`

### Testing Infrastructure
Zig:
- [x] Test utilities (temp dirs, cleanup helpers)
- [x] Fault injection hooks

Go:
- [ ] Integration test harness:
  - [ ] Start `pgz-server` on ephemeral port
  - [ ] Connect via pgx/lib/pq
  - [ ] Run queries and assert results

---

## M0: Storage Skeleton (macOS, Zig)

**Goal:** Crash-safe append-only primitives + minimal DB API.

### M0.1 types.zig — Foundation Types & Errors
- [x] `PageSize = 4096` constant
- [x] `SegmentId`, `Offset`, `Length` types
- [x] `ValuePointer` struct
- [x] `Epoch` type
- [x] Alignment helpers: `alignUp`, `isAligned`
- [ ] Error sets: `StorageError`, `CorruptionError`, `IOError`

### M0.2 crc32c.zig — Checksums
- [x] `crc32c(data) -> u32`
- [ ] `crc32cUpdate(crc, data) -> u32` (streaming)
- [ ] Hardware acceleration check
- [x] Test vectors: empty, known vectors, large input

### M0.3 io.zig — Platform I/O Abstraction (macOS first)

**Common interface:**
- [x] `IOOp` union: read/write/fsync
- [x] `Completion` struct

**macOS backend:**
- [ ] `F_NOCACHE` via `fcntl()`
- [ ] `F_FULLFSYNC` for durability
- [ ] `F_PREALLOCATE` for space reservation
- [ ] Aligned buffer allocation
- [ ] Short read/write loops
- [ ] Alignment assertions
- [ ] Tests: round-trip, alignment enforcement

**Fallback/test backend:**
- [ ] Synchronous backend
- [ ] I/O trace logging

### M0.4 vlog.zig — Value Log + Recovery

**Writer:**
- [ ] `append(payload) -> ValuePointer`
- [ ] `sync()` — flush to disk
- [ ] Segment rotation

**Reader:**
- [ ] `read(vptr) -> payload` (verify CRC)
- [ ] Handle corruption/EOF

**Recovery:**
- [ ] `scanLastGood()` — find last valid record
- [ ] Truncate to last valid on recovery
- [ ] Tests: partial write, corrupted CRC, valid file

### M0.5 sstable.zig — Single Sorted Run

**Writer:**
- [ ] Block encoding (entries + CRC + padding)
- [ ] Fence index encode/decode
- [ ] `finish() -> SSTableMetadata`

**Reader:**
- [ ] `open(path) -> SSTableReader`
- [ ] `get(key) -> ?ValuePointer`
- [ ] `iterator() -> SSTableIterator`
- [ ] Tests: point lookup, iteration, corruption

### M0.6 manifest.zig — Superblock + Manifest

**Superblock:**
- [ ] Two-copy read (pick valid by CRC)
- [ ] Atomic swap (write → fsync → update pointer)

**Manifest:**
- [ ] Append entries
- [ ] Replay to reconstruct state
- [ ] Checkpoint/compact

**Recovery:**
- [ ] Open superblock → replay manifest → validate files → vlog scan

### M0.7 commit_log.zig — Durability Primitive
- [ ] Commit record encoding/decoding
- [ ] Append + fsync API

### M0.8 db.zig — Minimal High-level API
- [ ] `DB.open(path)`
- [ ] `DB.close()`
- [ ] `DB.put(key, value)`
- [ ] `DB.get(key)`
- [ ] `DB.scan(from, to)`
- [ ] `DB.flush()` — create SSTable run

### M0 Exit Criteria
- [ ] Zig tests pass on macOS
- [ ] Open DB, put/get keys, persist, reopen, read
- [ ] Recovery handles truncated vlog without crash/corruption

---

## M1: LSM + Compaction + GC Hooks (Zig)

**Goal:** Multi-level LSM, background compaction, vLog GC accounting.

### M1.1 lsm.zig — MemTable + Levels + Flush
- [ ] MemTable structure (ordered map)
- [ ] Flush MemTable → SSTable L0
- [ ] Read path merges MemTable + L0..Ln

### M1.2 Compaction
- [ ] Tiered→leveled policy
- [ ] Choose candidates, merge, update manifest
- [ ] Correctness tests (no lost keys)

### M1.3 vLog GC Hooks
- [ ] Track live bytes vs garbage bytes per segment
- [ ] Record references from LSM entries
- [ ] (Optional) Segment rewrite GC

### M1.4 Throttling / Backpressure
- [ ] Compaction budget knobs
- [ ] Admission control (slow writes if L0 too large)

### M1 Exit Criteria
- [ ] Sustained writes trigger flush + compaction without data loss
- [ ] Read correctness across levels
- [ ] Manifest accurate after restart

---

## M2: Transactions + MVCC + Correctness (Zig)

**Goal:** Snapshot isolation, crash-correct recovery for committed txns.

### M2.1 txn.zig — Tx Lifecycle + MVCC
- [ ] txid/epoch assignment
- [ ] `txn_begin()`, `txn_commit()`, `txn_abort()`
- [ ] Visibility rules (reads see snapshot at begin)
- [ ] Write-write conflict detection

### M2.2 Commit Durability
- [ ] Durable iff commit record + vlog appends stable
- [ ] Group commit window
- [ ] Recovery replays commit log

### M2.3 Range Scans under MVCC
- [ ] Iterators respect snapshot visibility
- [ ] Phantom/version visibility tests

### M2.4 Crash Testing
- [ ] No dangling vptr after restart
- [ ] CRC failures surfaced, not silent
- [ ] Fault injection during vlog append, manifest update, compaction

### M2 Exit Criteria
- [ ] Transactional put/get with snapshot semantics
- [ ] Crash/restart preserves committed, discards uncommitted
- [ ] Compaction + transactions don't violate visibility

---

## M2.5: FFI / C API Stabilization (Zig + Go)

**Goal:** Complete, correct, stable ABI for Go server.

### M2.5.1 C ABI Contract (capi.zig + pgz.h)
- [x] Opaque handles: `DB*`, `Transaction*`, `Iterator*`
- [x] Error codes: `PGZ_OK`, `PGZ_ERR`, `PGZ_NOT_FOUND`
- [ ] `pgz_strerror(code)` or `pgz_last_error(db)`
- [x] Memory ownership documented in header

### M2.5.2 Core Operations
- [x] `pgz_open` / `pgz_close`
- [x] `pgz_get` / `pgz_put` / `pgz_delete`
- [x] `pgz_txn_begin` / `pgz_txn_commit` / `pgz_txn_abort`
- [x] `pgz_scan` / `pgz_iter_next` / `pgz_iter_close`
- [x] `pgz_free`
- [x] `pgz_version`

### M2.5.3 Go Binding Hardening
- [x] Build/link via cgo on macOS
- [ ] Translate error codes to Go `error`
- [ ] Always call `pgz_free` where required
- [ ] Go unit tests:
  - [ ] open/close
  - [ ] put/get
  - [ ] scan
  - [ ] txn begin/commit/abort

### M2.5 Exit Criteria
- [ ] `go test ./server/pkg/storage` passes
- [ ] No memory leaks in basic tests

---

## M3: Go Server (pgwire + SQL + planner)

**Goal:** Running `pgz-server` accepts Postgres clients, parses SQL, executes via Zig.

### M3.1 pgwire (Go) — PostgreSQL v3 Protocol

**Connection handling:**
- [ ] Listener + connection loop
- [ ] StartupMessage parsing
- [ ] Trust auth (no password for v1)

**Server messages:**
- [ ] AuthenticationOk
- [ ] ParameterStatus (minimal)
- [ ] ReadyForQuery

**Simple Query flow:**
- [ ] Accept `Q` message
- [ ] Send RowDescription / DataRow / CommandComplete
- [ ] Handle `Terminate`
- [ ] ErrorResponse (map errors to SQLSTATE)

### M3.2 parser (Go) — Minimal SQL Subset
- [ ] `CREATE TABLE t (pk INT PRIMARY KEY, v TEXT)`
- [ ] `INSERT INTO t (pk, v) VALUES (...)`
- [ ] `SELECT pk, v FROM t WHERE pk = ...`
- [ ] `BEGIN`, `COMMIT`, `ROLLBACK`
- [ ] (Optional) `DELETE FROM t WHERE pk = ...`

### M3.3 planner/executor (Go) — Catalog + KV Mapping

**Catalog:**
- [ ] In-memory table definitions (name, columns, pk)
- [ ] Persist to storage (optional in M3)

**Key encoding:**
- [ ] table prefix + pk bytes → key
- [ ] row encoding → value

**Execution:**
- [ ] Autocommit mode + explicit txn blocks
- [ ] SELECT-by-pk → `storage.Get`
- [ ] INSERT → `storage.Put`

**Result formatting:**
- [ ] RowDescription from schema
- [ ] DataRow encoding for int/text/null

### M3.4 Server Wiring
- [ ] `--data-dir` flag
- [ ] `--listen-addr` flag
- [ ] Graceful shutdown

### M3.5 Integration Tests
- [ ] `psql` smoke test: connect, create table, insert, select
- [ ] Go integration tests via pgx
- [ ] (Optional) SQLLogicTest subset

### M3 Exit Criteria
- [ ] `psql` connects and runs: `CREATE TABLE`, `INSERT`, `SELECT`, `BEGIN/COMMIT`
- [ ] Go integration tests pass
- [ ] Path: pgwire → parser → planner → `pkg/storage` → Zig engine

---

## M4: Observability + QoS Polish

**Goal:** Metrics, histograms, SLO-aware tuning.

### Metrics (Go server)
- [ ] `/metrics` endpoint (Prometheus format)
- [ ] Counters: queries_total, errors_total, storage ops
- [ ] Latency histograms

### Admin Commands
- [ ] `COMPACT` — trigger compaction
- [ ] `VACUUM` — trigger vLog GC

### M4 Exit Criteria
- [ ] Latency distributions observable
- [ ] p99 remains within SLO under background work

---

## M5: ZNS Backend (Optional, Zig)

- [ ] Zone management + sequential write enforcement
- [ ] Compaction/GC adapted to zone reset
- [ ] Benchmarks: lower WAF, tighter p99

---

## Ongoing / Cross-Cutting

### Linux Backend (post-M0)
- [ ] io_uring backend
- [ ] O_DIRECT support
- [ ] fdatasync/fsync testing

### Windows Backend (future)
- [ ] IOCP research + implementation

### Documentation
- [ ] "How to run" docs
- [ ] On-disk format versioning policy
- [ ] FFI contract documentation

---

## Priority Order

### Critical Path
1. **Pre-M0**: Build/test scaffolding
2. **M0**: Zig storage primitives + recovery
3. **M1**: LSM + compaction
4. **M2**: MVCC + txn durability
5. **M2.5**: Stabilize C ABI + Go bindings
6. **M3**: Go server (pgwire + parser + planner)

### High Priority (after M3)
- **M4**: Observability, QoS, admin tooling

### Optional
- **M5**: ZNS backend
