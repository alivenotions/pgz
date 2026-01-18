#!/bin/bash
set -e

# Ensure Zig library is built
if [ ! -f "zig-out/lib/libpgz.dylib" ] && [ ! -f "zig-out/lib/libpgz.so" ]; then
    echo "Zig library not found. Building..."
    ./build-zig.sh
    echo ""
fi

echo "Building and running Go FFI example..."
echo ""

cd pgwire/example

# Set library path for runtime linking
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    export DYLD_LIBRARY_PATH="../../zig-out/lib:$DYLD_LIBRARY_PATH"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    export LD_LIBRARY_PATH="../../zig-out/lib:$LD_LIBRARY_PATH"
fi

go run main.go
