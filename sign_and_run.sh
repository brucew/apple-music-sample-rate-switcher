#!/bin/bash

# Configuration
BINARY=".build/release/AppleMusicSampleRateSwitcher"
ENTITLEMENTS="Entitlements.entitlements"
ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | awk -F'"' '{print $2}')

if [ -z "$ID" ]; then
    ID=$(security find-identity -v -p codesigning | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')
fi

if [ -z "$ID" ]; then
    echo "ERROR: No valid code signing identity found."
    exit 1
fi

echo "Using identity: $ID"

# Build
swift build -c release

# Sign
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$ID" "$BINARY"

if [ $? -eq 0 ]; then
    echo "SUCCESS: Binary signed with MusicKit entitlements."
    
    # Test if it's killed
    echo "Verifying binary execution..."
    ./$BINARY --help > /dev/null 2>&1
    RESULT=$?
    if [ $RESULT -eq 137 ] || [ $RESULT -eq 9 ]; then
        echo "--------------------------------------------------------------------------------"
        echo "WARNING: The binary was KILLED by macOS. This usually means you added the "
        echo "'com.apple.developer.music' entitlement but don't have a provisioning profile."
        echo ""
        echo "To fix this, you have two options:"
        echo "1. Create a Provisioning Profile in the Apple Developer Portal for this Bundle ID,"
        echo "   download it, and sign with: codesign --provisioning-profile path/to/profile ..."
        echo "2. Clear Entitlements.entitlements (remove the music key) and run this script again."
        echo "   The tool will then use 'Log Stream' and 'AppleScript' fallbacks instead."
        echo "--------------------------------------------------------------------------------"
    fi
else
    echo "FAILED: Signing failed."
fi
