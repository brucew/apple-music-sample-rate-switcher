#!/bin/bash

# Simple build script for Apple Music Sample Rate Switcher
# No special signing requirements - just builds and optionally signs with ad-hoc identity

BINARY=".build/release/AppleMusicSampleRateSwitcher"

echo "Building..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "FAILED: Build failed."
    exit 1
fi

echo "SUCCESS: Build complete."
echo "Binary located at: $BINARY"
echo ""
echo "Run with: $BINARY --help"
