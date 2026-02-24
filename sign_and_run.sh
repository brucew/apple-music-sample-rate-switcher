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
if [ -f "embedded.provisionprofile" ]; then
    echo "Using embedded.provisionprofile found in current directory..."
    # On macOS, you can't easily embed a profile in a bare binary with codesign alone, 
    # but we'll try to sign with the entitlements and assume the user has installed the profile to 
    # ~/Library/MobileDevice/Provisioning Profiles/
fi

codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$ID" "$BINARY"

if [ $? -eq 0 ]; then
    echo "SUCCESS: Binary signed with entitlements."
    
    # Test if it's killed
    echo "Verifying binary execution..."
    ./$BINARY --help > /dev/null 2>&1
    RESULT=$?
    if [ $RESULT -eq 137 ] || [ $RESULT -eq 9 ]; then
        echo "--------------------------------------------------------------------------------"
        echo "WARNING: The binary was KILLED by macOS. This is expected if you have "
        echo "'com.apple.developer.music' in your entitlements but no matching "
        echo "Provisioning Profile installed on your Mac."
        echo ""
        echo "HOW TO FIX THIS:"
        echo "1. Create an App ID on developer.apple.com with 'MusicKit' capability."
        echo "2. Create a macOS Development Provisioning Profile for that App ID."
        echo "3. Download and DOUBLE-CLICK the .provisionprofile to install it."
        echo "4. Ensure the CFBundleIdentifier in Info.plist matches your App ID."
        echo "5. Run this script again."
        echo ""
        echo "ALTERNATIVE (LITE MODE):"
        echo "Remove the 'com.apple.developer.music' entitlement from $ENTITLEMENTS."
        echo "The tool will still work perfectly using Log Stream and AppleScript fallbacks."
        echo "--------------------------------------------------------------------------------"
    fi
else
    echo "FAILED: Signing failed."
fi
