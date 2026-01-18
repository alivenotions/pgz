# FFI Architecture

This document explains the FFI (Foreign Function Interface) implementation between Go and Zig in the pgz project.

## Overview

The project uses **cgo** to enable Go code to call into Zig code. The Zig code is compiled into a shared library (`.dylib` on macOS, `.so` on Linux) that Go dynamically links against at runtime.

## Architecture Layers

```
┌──────────────────────────────────────────────────────────┐
│ Application Layer (pgwire/example/main.go)               │
│ - User-facing code                                        │
│ - Calls Go API methods                                    │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────┐
│ Go Wrapper Layer (pgwire/db.go)                          │
│ - Idiomatic Go API                                        │
│ - Error handling (Go errors)                             │
│ - Memory safety (copies data, manages lifetimes)         │
│ - Provides: Open(), Close(), Put(), Get(), Delete()      │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼ cgo (FFI boundary)
┌──────────────────────────────────────────────────────────┐
│ C API Layer (src/ffi.zig)                                │
│ - C-compatible function signatures                        │
│ - Simple types only (pointers, sizes, error codes)       │
│ - Exports: pgz_db_open, pgz_put, pgz_get, etc.          │
└────────────────────┬─────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────┐
│ Zig Implementation Layer (src/db.zig)                    │
│ - Core business logic                                     │
│ - In-memory HashMap storage                              │
│ - Zig-native types and error handling                    │
└──────────────────────────────────────────────────────────┘
```

## Data Flow Example: Put Operation

Let's trace a `Put("user:1", "Alice")` call through all layers:

### 1. Application Layer (Go)
```go
// pgwire/example/main.go
err := db.Put([]byte("user:1"), []byte("Alice"))
```

### 2. Go Wrapper Layer (Go + cgo)
```go
// pgwire/db.go
func (db *DB) Put(key, value []byte) error {
    // Convert Go slices to C pointers
    keyPtr := (*C.uint8_t)(unsafe.Pointer(&key[0]))
    valuePtr := (*C.uint8_t)(unsafe.Pointer(&value[0]))

    // Call C function (crosses FFI boundary)
    errCode := C.pgz_put(
        db.handle,
        keyPtr,
        C.size_t(len(key)),
        valuePtr,
        C.size_t(len(value)),
    )

    // Convert C error code to Go error
    return mapError(errCode)
}
```

### 3. C API Layer (Zig)
```zig
// src/ffi.zig
export fn pgz_put(
    handle: *DBHandle,
    key: [*]const u8,
    key_len: usize,
    value: [*]const u8,
    value_len: usize,
) ErrorCode {
    // Cast opaque handle to concrete type
    const db_ptr: *db_mod.DB = @ptrCast(@alignCast(handle));

    // Convert C arrays to Zig slices
    const key_slice = key[0..key_len];
    const value_slice = value[0..value_len];

    // Call Zig implementation
    db_ptr.put(key_slice, value_slice) catch {
        return ErrorCode.OUT_OF_MEMORY;
    };

    return ErrorCode.OK;
}
```

### 4. Zig Implementation Layer (Zig)
```zig
// src/db.zig
pub fn put(self: *DB, key: []const u8, value: []const u8) !void {
    // Make copies (for ownership)
    const key_copy = try self.allocator.dupe(u8, key);
    const value_copy = try self.allocator.dupe(u8, value);

    // Store in HashMap
    try self.data.put(key_copy, value_copy);
}
```

## Memory Management

### Critical Rules

1. **Ownership:** Each side owns its own memory
2. **No sharing:** Never share pointers across the boundary
3. **Copy always:** When crossing FFI, copy data

### Detailed Flow

#### Go → Zig (Put operation)

```
Go Memory                 FFI Boundary           Zig Memory
─────────────────────────────────────────────────────────
key = []byte("user:1")
                          →  key pointer
                             (temporary, read-only)
                                                  key_copy = dupe(key)
                                                  (Zig owns this)
                          ←  return OK

Go keeps key
(Go GC manages it)                               Zig keeps key_copy
                                                 (Zig allocator manages it)
```

#### Zig → Go (Get operation)

```
Go Memory                 FFI Boundary           Zig Memory
─────────────────────────────────────────────────────────
                                                  value = HashMap.get(key)
                                                  value_copy = alloc(value.len)
                                                  copy(value_copy, value)

                          ←  value_copy pointer
                             (Zig allocator owns this)
C.GoBytes(value_ptr)
(makes Go copy)

pgz_free(value_ptr)       →  free value_copy
                             (Zig deallocates)

result = Go copy                                  (freed)
(Go GC manages it)
```

### Why This Approach?

**Safety:**
- Each runtime manages its own memory
- No dangling pointers (Zig can't free Go memory, Go can't free Zig memory)
- Clear ownership model

**Trade-off:**
- Extra memory copies
- Slightly higher overhead (~100-500ns per call)
- **BUT:** Negligible compared to network latency (1-100ms)

## Error Handling

### Zig Error Codes
```zig
pub const ErrorCode = enum(c_int) {
    OK = 0,
    NOT_FOUND = 1,
    OUT_OF_MEMORY = 2,
    INVALID_ARG = 3,
    UNKNOWN = 99,
};
```

### Go Error Mapping
```go
var (
    ErrNotFound    = errors.New("key not found")
    ErrOutOfMemory = errors.New("out of memory")
    ErrInvalidArg  = errors.New("invalid argument")
    ErrUnknown     = errors.New("unknown error")
)

func mapError(code C.ErrorCode) error {
    switch code {
    case C.NOT_FOUND:
        return ErrNotFound
    // ... etc
    }
}
```

### Why Error Codes?

- **Can't pass Zig error unions across FFI** (Zig-specific concept)
- **C-compatible** (simple integers)
- **Fast** (no allocations, just integer comparison)

## Type Mapping

| Go Type | C Type (cgo) | Zig Type |
|---------|--------------|----------|
| `[]byte` | `*C.uint8_t` + `C.size_t` | `[*]const u8` + `usize` → `[]const u8` |
| `error` | `C.ErrorCode` (int) | `ErrorCode` enum |
| `*DB` | `C.DBHandle` (void*) | `*DBHandle` (opaque) → `*db.DB` |

### Opaque Handles

**Why not expose `*db.DB` directly?**

```zig
// ❌ BAD: Exposes Zig internals to C
export fn pgz_put(db: *db.DB, ...) ErrorCode { ... }

// ✅ GOOD: Hides implementation
pub const DBHandle = opaque {};

export fn pgz_put(handle: *DBHandle, ...) ErrorCode {
    const db: *db.DB = @ptrCast(@alignCast(handle));
    // ...
}
```

**Benefits:**
- C/Go don't need to know Zig struct layout
- Can change `db.DB` without breaking FFI
- Type safety (can't accidentally pass wrong pointer)

## Build Process

### 1. Zig Compilation

```bash
zig build
```

**What happens:**
1. `build.zig` defines a `SharedLibrary` target
2. Zig compiles `src/ffi.zig` (which imports `src/db.zig`)
3. Outputs `libpgz.dylib` (macOS) or `libpgz.so` (Linux) to `zig-out/lib/`
4. Exports C symbols: `pgz_db_open`, `pgz_put`, `pgz_get`, etc.

### 2. Go Compilation

```bash
cd pgwire/example
go run main.go
```

**What happens:**
1. Go processes `import "C"` comment block in `db.go`
2. cgo reads `#cgo LDFLAGS: -L../../zig-out/lib -lpgz`
3. cgo generates C→Go bridge code
4. Go linker links against `libpgz.dylib`
5. At runtime, dynamic linker loads the shared library

### Runtime Linking

**macOS:**
```bash
export DYLD_LIBRARY_PATH=../../zig-out/lib:$DYLD_LIBRARY_PATH
```

**Linux:**
```bash
export LD_LIBRARY_PATH=../../zig-out/lib:$LD_LIBRARY_PATH
```

This tells the dynamic linker where to find `libpgz` at runtime.

## Performance Characteristics

### FFI Overhead

| Operation | Overhead | Notes |
|-----------|----------|-------|
| Function call | ~50-200ns | Crossing FFI boundary |
| Memory copy (1KB) | ~100ns | Go→Zig or Zig→Go |
| Error code mapping | ~5ns | Simple switch statement |

### Context: Network Latency

| Network Type | Latency | FFI as % |
|--------------|---------|----------|
| Localhost TCP | ~0.1ms | 0.2% |
| LAN | 1-10ms | 0.002-0.02% |
| Internet | 20-100ms | 0.0001-0.001% |

**Conclusion:** FFI overhead is negligible for a network-facing database.

## Future Enhancements

### Batch Operations

Instead of:
```go
for _, key := range keys {
    db.Get(key)  // N FFI calls
}
```

Could do:
```go
db.BatchGet(keys)  // 1 FFI call
```

### Zero-Copy Reads (Advanced)

For read-only operations, could use shared memory:
```go
// Go borrows Zig memory (unsafe, but zero-copy)
value := db.GetView(key)  // Returns slice backed by Zig memory
// Must not modify value
// Must finish using before next FFI call
```

**Trade-off:** Complexity vs. performance gain (probably not worth it for network DB).

## References

- [cgo documentation](https://pkg.go.dev/cmd/cgo)
- [Zig export documentation](https://ziglang.org/documentation/master/#export)
- [WiscKey paper](https://www.usenix.org/system/files/conference/fast16/fast16-papers-lu.pdf) (inspiration for storage layer)
