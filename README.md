# Apple Music Sample Rate Switcher

A lightweight macOS daemon that automatically switches your DAC's sample rate to match the current Apple Music track's native sample rate — within ~100ms of playback start.

## The Problem

Apple Music (Music.app) resamples all audio to match the output device's current sample rate before sending it to the DAC. Unlike audiophile players (Roon, Audirvana), Music.app never calls CoreAudio to switch the device sample rate. This means if your DAC is set to 44.1kHz and you play a 96kHz Hi-Res Lossless track, Music.app silently downsamples it.

## How It Works

1. Listens for `com.apple.Music.playerInfo` distributed notifications (fires instantly on play/pause/skip)
2. Monitors macOS system logs in real-time (`log stream`) for `activeFormat` events from Music.app
3. On "Playing" event, concurrently:
   - Queries the track's native sample rate via AppleScript (for local files)
   - Queries Apple Music Catalog via MusicKit or iTunes API (for streaming tracks)
   - Uses the latest rate detected by the log monitor as the final source of truth
4. If the DAC's current rate doesn't match, switches it via CoreAudio's `AudioObjectSetPropertyData`
5. Music.app then outputs at the new (matching) rate — bit-perfect, no resampling

Total latency from playback start to DAC switch: **~10–100ms** (near-instant due to real-time log monitoring and metadata caching).

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+
- An Apple Music subscription with Lossless enabled in Music.app settings
- A DAC that supports multiple sample rates
- **Apple Developer ID** (required for MusicKit entitlements)

## Setup

### 1. Enable Lossless in Music.app

Open **Music.app** → `Settings` → `Playback` → set Audio Quality to **Lossless** or **Hi-Res Lossless**.

### 2. Build

```bash
cd /Users/brucew/Projects/apple-music-sample-rate-switcher
swift build -c release
```

The binary will be at `.build/release/AppleMusicSampleRateSwitcher`.

### 3. Sign the Binary

To use MusicKit (required for accurate streaming sample rates), the binary must be signed with your Developer ID and include the proper entitlements and an embedded `Info.plist`.

1. **Find your signing identity**:
```bash
security find-identity -v -p codesigning
```

2. **Run the provided signing script**:
This script will build the project and sign it with your Developer ID identity.
```bash
chmod +x sign_and_run.sh
./sign_and_run.sh
```

Alternatively, you can sign manually:
```bash
# Build
swift build -c release

# Sign with entitlements and Info.plist (already embedded in the binary by the build process)
codesign --force --options runtime --entitlements Entitlements.entitlements --sign "Developer ID Application: YOUR NAME" .build/release/AppleMusicSampleRateSwitcher
```

### 4. MusicKit & Permissions

This tool uses MusicKit to fetch high-resolution metadata for streaming tracks. 

#### If MusicKit says "Denied":
This is common for command-line tools on macOS. The switcher will automatically fall back to:
1. **Real-time Log Monitoring (`log stream`)**: This is extremely fast and accurate as it watches what Music.app is actually doing.
2. **iTunes Lookup API**: For basic track metadata.
3. **AppleScript**: For local files.

#### If the binary is "Killed" on launch:
This means you added the `com.apple.developer.music` entitlement but don't have a matching **Provisioning Profile**. 
- To use MusicKit properly, you need to create a profile in the Apple Developer portal for the bundle ID `com.brucew.AppleMusicSampleRateSwitcher`.
- **Alternatively**, just remove the entitlement from `Entitlements.entitlements` and re-sign. The tool will run perfectly using the Log and AppleScript fallbacks.

If you don't see the prompt or get an error, go to **System Settings > Privacy & Security > Media & Apple Music** and ensure the terminal or app is enabled.

### 5. Find Your DAC's UID

```bash
.build/release/AppleMusicSampleRateSwitcher --list-devices
```

This lists all audio output devices with their UIDs and supported sample rates.

### 6. Run

```bash
# Use default output device:
.build/release/AppleMusicSampleRateSwitcher

# Use a specific DAC:
.build/release/AppleMusicSampleRateSwitcher --device-uid "YOUR_DAC_UID"
```

### 5. Test

Play a track in Music.app. You should see output like:

```
[2026-02-23 18:45:12.345] Player state: Playing — Bohemian Rhapsody by Queen
[2026-02-23 18:45:12.389] Track native sample rate: 96000 Hz
[2026-02-23 18:45:12.390] Switching DAC from 44100 Hz to 96000 Hz...
[2026-02-23 18:45:12.402] SUCCESS: DAC set to 96000 Hz (took 57.3 ms)
```

## Run as a Background Agent (launchd)

To have the switcher start automatically at login:

```bash
cp com.brucew.apple-music-sample-rate-switcher.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.brucew.apple-music-sample-rate-switcher.plist
```

Edit the plist to set your DAC UID and desired log path. To stop:

```bash
launchctl unload ~/Library/LaunchAgents/com.brucew.apple-music-sample-rate-switcher.plist
```

## Permissions

On first run, macOS may prompt you to grant:
- **Automation** permission (to control Music.app via AppleScript)
- Go to `System Settings` → `Privacy & Security` → `Automation` and ensure the terminal/app running the switcher can control "Music"

## Troubleshooting

- **"Could not determine track sample rate"**: Music.app may not expose `sample rate` for streaming tracks (only downloaded/matched). Try downloading the track first.
- **"Sample rate is not settable on this device"**: Some built-in audio devices (e.g., MacBook speakers) don't support rate switching. Use an external DAC.
- **No notifications firing**: Ensure Music.app (not a third-party player) is being used. The notification name is specific to Apple's Music app.
