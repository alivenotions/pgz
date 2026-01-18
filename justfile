# pgz justfile - Build and run commands

# Default recipe (shows available commands)
default:
    @just --list

# Build Zig shared library
build-zig:
    @echo "Building Zig shared library..."
    zig build
    @echo ""
    @echo "✓ Zig library built successfully!"
    @echo "  Library location: zig-out/lib/libpgz.dylib (macOS) or libpgz.so (Linux)"

# Run Zig tests
test-zig:
    @echo "Running Zig tests..."
    zig build test

# Build everything (Zig library)
build: build-zig
    @echo ""
    @echo "✓ All builds complete!"

# Run the Go FFI example
run-example: build-zig
    @echo "Running Go FFI example..."
    @echo ""
    #!/usr/bin/env bash
    cd pgwire/example
    if [[ "$OSTYPE" == "darwin"* ]]; then
        export DYLD_LIBRARY_PATH="../../zig-out/lib:$DYLD_LIBRARY_PATH"
    else
        export LD_LIBRARY_PATH="../../zig-out/lib:$LD_LIBRARY_PATH"
    fi
    go run main.go

# Run all tests (Zig tests + Go example as integration test)
test: test-zig run-example
    @echo ""
    @echo "✓ All tests passed!"

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rm -rf zig-out/
    @echo "✓ Clean complete!"

# Show library info
lib-info: build-zig
    @echo "Library information:"
    @echo ""
    @if [ -f "zig-out/lib/libpgz.dylib" ]; then \
        echo "macOS library:"; \
        ls -lh zig-out/lib/libpgz.dylib; \
        file zig-out/lib/libpgz.dylib; \
        echo ""; \
        echo "Exported symbols:"; \
        nm -g zig-out/lib/libpgz.dylib | grep " T " | head -20; \
    elif [ -f "zig-out/lib/libpgz.so" ]; then \
        echo "Linux library:"; \
        ls -lh zig-out/lib/libpgz.so; \
        file zig-out/lib/libpgz.so; \
        echo ""; \
        echo "Exported symbols:"; \
        nm -D zig-out/lib/libpgz.so | grep " T " | head -20; \
    else \
        echo "Library not found. Run 'just build' first."; \
    fi

# Check prerequisites
check-prereqs:
    @echo "Checking prerequisites..."
    @echo ""
    @which zig > /dev/null && echo "✓ Zig found: $(zig version)" || echo "✗ Zig not found"
    @which go > /dev/null && echo "✓ Go found: $(go version)" || echo "✗ Go not found"
    @which gcc > /dev/null && echo "✓ GCC found" || (which clang > /dev/null && echo "✓ Clang found" || echo "✗ No C compiler found")
    @echo ""
    @if ! which zig > /dev/null; then \
        echo "Install Zig from: https://ziglang.org/download/"; \
    fi
    @if ! which go > /dev/null; then \
        echo "Install Go from: https://go.dev/dl/"; \
    fi

# Development workflow: clean, build, test
dev: clean build test
    @echo ""
    @echo "✓ Development cycle complete!"

# Quick development loop (skip clean)
quick: build run-example

# Format Zig code
fmt:
    @echo "Formatting Zig code..."
    zig fmt src/*.zig build.zig
    @echo "✓ Formatting complete!"
