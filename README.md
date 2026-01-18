# pgz

A PostgreSQL-compatible database engine built from scratch in Zig with a Go-based wire protocol layer.

## Overview

This project implements a flash-native, SSD-optimized database storage engine in Zig, with plans to support the PostgreSQL wire protocol via a Go frontend. The architecture separates performance-critical storage operations (Zig) from network/protocol handling (Go) using FFI.

### Architecture

```
┌─────────────────────────────────────────────────┐
│  Single Process                                  │
│                                                  │
│  ┌─────────────┐    FFI calls   ┌─────────────┐│
│  │ Go Layer    │◄──────────────►│ Zig Core    ││
│  │ (pgwire)    │   via cgo      │ (storage)   ││
│  │             │                │             ││
│  │ • Protocol  │                │ • LSM tree  ││
│  │ • SQL parse │                │ • vLog      ││
│  │ • Network   │                │ • MVCC      ││
│  └─────────────┘                └─────────────┘│
└─────────────────────────────────────────────────┘
```

**Current Status:** Basic FFI layer implemented with in-memory key-value store. See [plan.md](plan.md) for full roadmap.

## Project Structure

```
pgz/
├── src/
│   ├── main.zig        # Main executable entry point
│   ├── types.zig       # Common type definitions
│   ├── db.zig          # Core database implementation (in-memory KV store)
│   └── ffi.zig         # C-compatible FFI layer for Go interop
├── pgwire/
│   ├── db.go           # Go wrapper with cgo bindings
│   └── example/
│       └── main.go     # Demo program showing FFI in action
├── build.zig           # Zig build configuration
├── justfile            # Build and run commands (recommended)
├── build-zig.sh        # Build Zig shared library (alternative)
├── run-example.sh      # Build and run Go FFI example (alternative)
├── FFI-ARCHITECTURE.md # Deep dive into FFI design
├── TESTING.md          # Testing guide
└── plan.md             # Full implementation plan

```

## Prerequisites

- **Zig** 0.13.0 or later ([download](https://ziglang.org/download/))
- **Go** 1.21 or later ([download](https://go.dev/dl/))
- **GCC/Clang** (for cgo)
- **just** (optional, recommended) - command runner ([install](https://github.com/casey/just#installation))

Check prerequisites:
```bash
just check-prereqs
```

## Quick Start

### Using `just` (Recommended)

```bash
# See all available commands
just

# Build and run the FFI example
just run-example

# Run all tests (Zig tests + Go example)
just test

# Development workflow (clean + build + test)
just dev

# Quick iteration (build + run, skip clean)
just quick
```

### Using Shell Scripts (Alternative)

```bash
# Build Zig library
./build-zig.sh

# Run Go FFI example
./run-example.sh
```

### Expected Output

```
=== PGZ FFI Demo ===
Demonstrating Go calling into Zig via FFI

Opening database...
✓ Database opened

Storing key-value pairs...
  PUT user:1 = Alice
  PUT user:2 = Bob
  PUT user:3 = Charlie
  PUT config:db = postgresql://localhost:5432
✓ All values stored

Retrieving values...
  GET user:1 = Alice
  GET user:2 = Bob
  GET user:3 = Charlie
  GET config:db = postgresql://localhost:5432
✓ All values retrieved

Testing overwrite...
  user:1 = Alice Updated
✓ Overwrite successful

Testing delete...
  Deleted user:2
  ✓ Confirmed user:2 is gone
✓ Delete successful

Testing error handling...
  ✓ Correctly returned ErrNotFound for missing key
  ✓ Correctly returned ErrInvalidArg for empty key

=== All tests passed! ===

This demonstrates:
  • Go → Zig FFI calls working correctly
  • Memory management across the boundary
  • Error handling via error codes
  • Basic database operations (Put, Get, Delete)
```

## Available Commands (just)

| Command | Description |
|---------|-------------|
| `just` | Show all available commands |
| `just run-example` | Build and run Go FFI example |
| `just test` | Run all tests (Zig + Go integration) |
| `just build` | Build Zig shared library |
| `just clean` | Remove build artifacts |
| `just dev` | Clean + build + test (full dev cycle) |
| `just quick` | Build + run (skip clean, faster iteration) |
| `just lib-info` | Show library details and exported symbols |
| `just check-prereqs` | Verify required tools are installed |
| `just fmt` | Format Zig code |

## Manual Build Steps

If you prefer to build manually without `just`:

### Build Zig Library

```bash
zig build
```

### Run Zig Tests

```bash
zig build test
```

### Build and Run Go Example

```bash
# macOS
cd pgwire/example
export DYLD_LIBRARY_PATH="../../zig-out/lib:$DYLD_LIBRARY_PATH"
go run main.go

# Linux
cd pgwire/example
export LD_LIBRARY_PATH="../../zig-out/lib:$LD_LIBRARY_PATH"
go run main.go
```

## FFI Interface

The FFI layer provides a C-compatible API that Go calls via cgo:

### Zig Side (src/ffi.zig)

```zig
// C-compatible error codes
pub const ErrorCode = enum(c_int) {
    OK = 0,
    NOT_FOUND = 1,
    OUT_OF_MEMORY = 2,
    INVALID_ARG = 3,
    UNKNOWN = 99,
};

// Exported functions
export fn pgz_db_open(handle: *?*DBHandle) ErrorCode;
export fn pgz_db_close(handle: *DBHandle) void;
export fn pgz_put(handle: *DBHandle, key: [*]const u8, key_len: usize,
                  value: [*]const u8, value_len: usize) ErrorCode;
export fn pgz_get(handle: *DBHandle, key: [*]const u8, key_len: usize,
                  value_out: *?[*]u8, value_len_out: *usize) ErrorCode;
export fn pgz_delete(handle: *DBHandle, key: [*]const u8, key_len: usize) ErrorCode;
export fn pgz_free(ptr: [*]u8, len: usize) void;
```

### Go Side (pgwire/db.go)

```go
// Go wrapper with idiomatic API
type DB struct {
    handle C.DBHandle
}

func Open() (*DB, error)
func (db *DB) Close()
func (db *DB) Put(key, value []byte) error
func (db *DB) Get(key []byte) ([]byte, error)
func (db *DB) Delete(key []byte) error
```

## Memory Management

The FFI layer follows a clear ownership model:

1. **Go → Zig:** Go keeps data alive during the call
2. **Zig → Go:** Zig allocates, Go copies, then frees Zig allocation via `pgz_free()`
3. No shared ownership across the boundary

Example from `pgwire/db.go`:
```go
// Get allocates in Zig, copies to Go, then frees Zig memory
value := C.GoBytes(unsafe.Pointer(valuePtr), C.int(valueLen))
C.pgz_free(valuePtr, valueLen)  // Free Zig allocation
return value, nil               // Return Go-owned copy
```

## Why Go + Zig?

### Zig for Storage Engine
- Manual memory management for predictable performance
- Zero-cost abstractions
- Fine-grained control over I/O and memory layout
- No runtime overhead (no GC pauses)
- Target: p99 latency < 1ms, WAF ≤ 3×

### Go for Wire Protocol
- Excellent networking libraries
- Built-in PostgreSQL protocol support
- Goroutines for concurrent client connections
- Network latency (1-100ms) dominates FFI overhead (0.0001ms)

## Development Roadmap

See [plan.md](plan.md) for the full implementation plan. High-level milestones:

- **M0:** Storage skeleton (vLog, SSTable, manifest) - *In Progress*
- **M1:** LSM + compaction + GC
- **M2:** MVCC with snapshot isolation
- **M3:** PostgreSQL wire protocol + minimal SQL
- **M4:** Observability + QoS polish

## Contributing

This is currently a learning/experimental project. See [plan.md](plan.md) for design decisions and architecture details.

## License

MIT
