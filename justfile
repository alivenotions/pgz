# pgz build commands

go := "/usr/local/go/bin/go"

# Build everything
default: build-zig build-server

# Build the Zig shared library
build-zig:
    zig build

# Build the server (requires Zig lib to be built first)
build-server: build-zig
    {{go}} build -C server -o ../bin/pgz-server ./cmd/pgz-server

# Run the server
run: build-server
    mkdir -p data
    ./bin/pgz-server ./data

# Run Zig tests
test-zig:
    zig build test

# Run server tests
test-server: build-zig
    {{go}} test -C server ./...

# Run all tests
test: test-zig test-server

# Clean build artifacts
clean:
    rm -rf zig-out .zig-cache bin
    {{go}} clean -C server

# Format code
fmt:
    zig build fmt
    {{go}} fmt -C server ./...

# Check formatting
fmt-check:
    zig build fmt-check
    {{go}} fmt -C server -n ./...
