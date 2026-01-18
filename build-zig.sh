#!/bin/bash
set -e

echo "Building Zig shared library..."
zig build

echo ""
echo "Build artifacts:"
ls -lh zig-out/lib/

echo ""
echo "✓ Zig library built successfully!"
echo "  Library location: zig-out/lib/libpgz.dylib (macOS) or libpgz.so (Linux)"
