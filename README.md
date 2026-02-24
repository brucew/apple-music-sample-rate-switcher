# Apple Music Sample Rate Switcher

A lightweight macOS daemon that automatically switches your DAC's sample rate to match the current Apple Music track's native sample rate — within ~500-700ms of playback start.

## The Problem

Apple Music (Music.app) resamples all audio to match the output device's current sample rate before sending it to the DAC. Unlike audiophile players (Roon, Audirvana), Music.app never calls CoreAudio to switch the device sample rate. This means if your DAC is set to 44.1kHz and you play a 96kHz Hi-Res Lossless track, Music.app silently downsamples it.

## How It Works

1. Listens for `com.apple.Music.playerInfo` distributed notifications (fires instantly on play/pause/skip)
2. Monitors macOS system logs in real-time (`log stream`) for `activeFormat` events from Music.app
3. When the log stream detects the actual sample rate being used, switches the DAC via CoreAudio's `AudioObjectSetPropertyData`
4. Music.app then outputs at the new (matching) rate — bit-perfect, no resampling

Total latency from playback start to DAC switch: **~500–700ms** (the time it takes for Music.app to report its format to the system log).

### Optional: Pause-During-Switch Mode

Use `--pause-during-switch` to eliminate audio glitches:
1. The tool pauses Music.app immediately when a new track starts
2. Waits for the log stream to detect the correct sample rate
3. Switches the DAC
4. Automatically resumes playback

This provides a seamless experience with no audible pops or glitches during rate changes.

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+
- An Apple Music subscription with Lossless enabled in Music.app settings
- A DAC that supports multiple sample rates

## Setup

### 1. Enable Lossless in Music.app

Open **Music.app** → `Settings` → `Playback` → set Audio Quality to **Lossless** or **Hi-Res Lossless**.

### 2. Build

```bash
swift build -c release
```

Or use the provided build script:
```bash
./build.sh
```

The binary will be at `.build/release/AppleMusicSampleRateSwitcher`.

### 3. Find Your DAC's UID

```bash
.build/release/AppleMusicSampleRateSwitcher --list-devices
```

This lists all audio output devices with their UIDs and supported sample rates.

### 4. Run

```bash
# Use default output device:
.build/release/AppleMusicSampleRateSwitcher

# Use a specific DAC:
.build/release/AppleMusicSampleRateSwitcher --device-uid "YOUR_DAC_UID"

# Use pause-during-switch for gapless switching:
.build/release/AppleMusicSampleRateSwitcher --device-uid "YOUR_DAC_UID" --pause-during-switch
```

### 5. Test

Play a track in Music.app. You should see output like:

```
[2026-02-23 21:30:12.345] Player state: Playing — Bohemian Rhapsody by Queen
[2026-02-23 21:30:12.890] Switching DAC from 44100 Hz to 96000 Hz... (Source: Log Stream)
[2026-02-23 21:30:12.891] SUCCESS: DAC set to 96000 Hz (switch took 0.5 ms, detected at +545.2 ms) (Source: Log Stream)
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
- **Automation** permission (to control Music.app via AppleScript for pause/resume)
- Go to `System Settings` → `Privacy & Security` → `Automation` and ensure the terminal/app running the switcher can control "Music"

## Troubleshooting

- **"Sample rate is not settable on this device"**: Some built-in audio devices (e.g., MacBook speakers) don't support rate switching. Use an external DAC.
- **No notifications firing**: Ensure Music.app (not a third-party player) is being used. The notification name is specific to Apple's Music app.
- **Slow detection**: The log stream typically detects the sample rate within 500-700ms. Use `--pause-during-switch` if you want to avoid hearing audio at the wrong rate.
