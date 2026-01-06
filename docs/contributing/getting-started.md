# Getting Started

## Prerequisites

- Zig 0.16.0-dev or later (nightly)
- macOS (primary development platform)

## Building

```bash
# Build the CLI
zig build

# Run tests
zig build test

# Run specific module tests
zig build test-types
zig build test-crc

# Format code
zig build fmt

# Check formatting
zig build fmt-check
```

## Project Structure

```
pgz/
├── src/           # Source code
├── docs/          # Documentation
├── plan.md        # Design document
└── tasks.md       # Implementation tasks
```

## Development Workflow

1. Read `plan.md` to understand the architecture
2. Check `tasks.md` for current milestone tasks
3. Pick an item marked with `[ ]` 
4. Implement with tests
5. Run `zig build test` before committing

## Coding Conventions

### Error Handling
- Return errors, don't panic (except for bugs)
- Use descriptive error names from `types.zig`

### Testing
- Every public function needs tests
- Use `testing.zig` utilities for temp directories
- Test edge cases: empty input, max sizes, corruption

### Documentation
- Doc comments on all public items (`///`)
- Module-level docs explaining purpose (`//!`)

## Current Focus: M0 (Storage Skeleton)

M0 exit criteria:
- [ ] Crash-safe vLog with recovery
- [ ] Single SSTable run
- [ ] Superblock with atomic updates
- [ ] Basic CLI: put, get, flush

See `tasks.md` for detailed task breakdown.
