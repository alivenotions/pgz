# Testing Guide

This document explains how to test the FFI integration between Go and Zig.

## Prerequisites

Before testing, ensure you have:
1. Zig 0.13.0+ installed
2. Go 1.21+ installed
3. GCC or Clang (for cgo)

## Testing Steps

### 1. Test Zig Code Only

First, verify the Zig implementation works independently:

```bash
zig build test
```

This runs all Zig unit tests including:
- `src/db.zig`: In-memory database tests
- `src/ffi.zig`: FFI layer tests (calling exported C functions from Zig)
- `src/root.zig`: Basic functionality tests

**Expected output:**
```
All 3 tests passed.
```

### 2. Build the Shared Library

Build the Zig shared library that Go will link against:

```bash
zig build
```

**Expected output:**
```
zig build
```

Verify the library was created:

```bash
# macOS
ls -lh zig-out/lib/libpgz.dylib

# Linux
ls -lh zig-out/lib/libpgz.so
```

### 3. Test FFI Integration

Run the Go example that demonstrates the FFI working:

```bash
./run-example.sh
```

**Expected output:**
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
```

### 4. Manual Testing

You can also test the Go bindings manually:

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

## Troubleshooting

### "cannot find -lpgz"

This means cgo can't find the Zig shared library. Solutions:

1. Make sure you ran `zig build` first
2. Verify the library exists in `zig-out/lib/`
3. Check that `DYLD_LIBRARY_PATH` (macOS) or `LD_LIBRARY_PATH` (Linux) is set correctly

### "zig: command not found"

Install Zig from https://ziglang.org/download/

### cgo errors

Make sure you have a C compiler installed:
- macOS: Install Xcode Command Line Tools: `xcode-select --install`
- Linux: Install GCC: `sudo apt-get install build-essential` (Ubuntu/Debian)

### Segmentation fault

This usually indicates a memory management issue across the FFI boundary. Check:
1. Are you calling `pgz_free()` for every value returned by `pgz_get()`?
2. Are you keeping Go slices alive during FFI calls?
3. Are the error codes being checked properly?

## What the Tests Verify

### Zig Tests (src/ffi.zig)
- Database can be opened and closed
- Put operation stores values correctly
- Get operation retrieves values
- Delete operation removes values
- Error codes work correctly (NOT_FOUND, INVALID_ARG)
- Memory is properly allocated and freed

### Go FFI Tests (pgwire/example/main.go)
- FFI calls from Go to Zig work
- Data passes correctly across the boundary
- Memory management works (no leaks)
- Error handling works (Go errors map to Zig error codes)
- All basic operations work: Put, Get, Delete

## Performance Testing (TODO)

Future tests should measure:
- FFI call overhead (should be ~50-200ns)
- Memory copying overhead
- Throughput (operations per second)

Run with:
```bash
go test -bench=. -benchmem ./pgwire/
```

## Memory Leak Testing (TODO)

Use valgrind or Go's race detector:

```bash
# Go race detector
go run -race main.go

# Valgrind (if available)
valgrind --leak-check=full ./zig-out/bin/pgz
```
