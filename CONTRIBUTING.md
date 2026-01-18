# Contributing to pgz

Thank you for your interest in contributing to pgz!

## Development Setup

### Prerequisites

- **Zig** 0.13.0 or later ([download](https://ziglang.org/download/))
- **Go** 1.21 or later ([download](https://go.dev/dl/))
- **GCC/Clang** (for cgo)
- **just** (recommended) - command runner ([install](https://github.com/casey/just#installation))

Verify your setup:
```bash
just check-prereqs
```

## Code Formatting

### Zig Code

All Zig code **must** be formatted with `zig fmt` before committing. The CI will fail if code is not properly formatted.

**Format all Zig files:**
```bash
zig fmt .

# Or using just:
just fmt
```

**Check formatting without modifying files:**
```bash
zig fmt --check .
```

### Auto-formatting on CI

For branches starting with `claude/`, GitHub Actions will automatically format Zig code and commit the changes. For other branches, you must format locally before pushing.

## Testing

### Run All Tests
```bash
just test
```

This runs:
1. Zig unit tests (`zig build test`)
2. Go FFI integration test (`pgwire/example/main.go`)

### Run Only Zig Tests
```bash
just test-zig
```

### Run Only Integration Test
```bash
just run-example
```

## Build Commands

See all available commands:
```bash
just
```

Common commands:
- `just build` - Build Zig shared library
- `just test` - Run all tests
- `just dev` - Clean + build + test
- `just quick` - Build + run (fast iteration)
- `just clean` - Remove build artifacts

## Development Workflow

1. **Make changes** to Zig or Go code
2. **Format Zig code**: `just fmt` or `zig fmt .`
3. **Run tests**: `just test`
4. **Commit**: Standard git workflow
5. **Push**: CI will run tests and formatting checks

## Project Structure

- `src/` - Zig storage engine implementation
- `pgwire/` - Go wrapper with cgo bindings
- `build.zig` - Zig build configuration
- `justfile` - Build and test commands

## Coding Guidelines

### Zig

- Follow Zig's standard formatting (enforced by `zig fmt`)
- Use meaningful variable names
- Add tests for new functionality
- Document public APIs with `///` comments
- Keep functions focused and small

### Go

- Follow Go standard formatting (`go fmt`)
- Use meaningful variable names
- Add tests for new functionality
- Handle errors explicitly
- Document exported types and functions

### FFI Boundary

When working across the Go/Zig FFI boundary:

1. **Memory management**: Each side owns its own memory
   - Go→Zig: Go keeps data alive during call
   - Zig→Go: Zig allocates, Go copies, Zig frees

2. **Error handling**: Use error codes, not error unions
   - Zig exports C-compatible error codes
   - Go maps them to Go errors

3. **Type safety**: Use opaque handles, not direct pointers
   - Hide implementation details
   - Prevent accidental type misuse

See [FFI-ARCHITECTURE.md](FFI-ARCHITECTURE.md) for detailed information.

## Commit Messages

Use clear, descriptive commit messages:

```
Add feature X to support Y

- Implemented Z in src/foo.zig
- Added tests for edge case A
- Updated documentation

Fixes #123
```

## CI/CD

The CI runs on all pull requests and pushes:

1. **Build & Test** (Ubuntu, macOS, Windows)
   - `zig build test`

2. **Lint** (Ubuntu)
   - `zig fmt --check .`

3. **Auto-format** (claude/* branches only)
   - Automatically formats and commits Zig code

All checks must pass before merging.

## Getting Help

- Check [README.md](README.md) for basic usage
- Read [plan.md](plan.md) for architecture and design decisions
- See [FFI-ARCHITECTURE.md](FFI-ARCHITECTURE.md) for FFI details
- Review [TESTING.md](TESTING.md) for testing guidance

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
