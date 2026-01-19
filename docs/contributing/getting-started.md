# Getting Started

## Prerequisites

- Zig 0.16.0-dev or later (nightly)
- Go 1.21 or later
- [just](https://github.com/casey/just) command runner
- macOS (primary development platform)

## Building

```bash
# Build everything (Zig library + Go server)
just

# Build only the Zig storage engine
just build-zig

# Build only the Go server
just build-server

# Run the server
just run

# Run all tests
just test

# Format code
just fmt

# Clean build artifacts
just clean
```

## Project Structure

```
pgz/
├── src/           # Zig storage engine (LSM, vLog, I/O)
│   ├── capi.zig   # C API for FFI with Go
│   ├── db.zig     # High-level database API
│   ├── lsm.zig    # LSM tree implementation
│   ├── vlog.zig   # Value log (append-only)
│   └── ...
├── server/        # Go server (wire protocol, SQL)
│   ├── cmd/       # Server entry point
│   └── pkg/
│       └── storage/  # Go bindings to Zig via cgo
├── include/       # C headers for FFI
│   └── pgz.h
├── docs/          # Documentation
├── plan.md        # Design document
├── tasks.md       # Implementation tasks
└── justfile       # Build commands
```

## Architecture

The project is split into two layers:

| Layer | Language | Responsibility |
|-------|----------|----------------|
| **Storage Engine** | Zig | LSM tree, vLog, I/O, transactions, checksums |
| **Server** | Go | PostgreSQL wire protocol, SQL parsing, query planning |

Communication happens via FFI (Zig exports C API, Go calls via cgo).

## Development Workflow

1. Read `plan.md` to understand the architecture
2. Check `tasks.md` for current milestone tasks
3. Pick an item marked with `[ ]` 
4. Implement with tests
5. Run `just test` before committing

## Coding Conventions

### Zig (Storage Engine)

- Return errors, don't panic (except for bugs)
- Use descriptive error names from `types.zig`
- Doc comments on all public items (`///`)
- Module-level docs explaining purpose (`//!`)
- All I/O must be 4KiB-aligned

### Go (Server)

- Follow standard Go conventions
- Handle errors explicitly
- Use the `storage` package for all DB operations

### Testing

- Every public function needs tests
- Use `testing.zig` utilities for temp directories
- Test edge cases: empty input, max sizes, corruption

## Current Focus: M0 (Storage Skeleton)

M0 exit criteria:
- [ ] Crash-safe vLog with recovery
- [ ] Single SSTable run
- [ ] Superblock with atomic updates
- [ ] Basic CLI: put, get, flush

See `tasks.md` for detailed task breakdown.
