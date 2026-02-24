import Foundation
import CoreAudio
import AudioToolbox

// MARK: - CoreAudio Helpers

private func getStringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0, nil,
        &dataSize,
        &value
    )
    guard status == noErr, let cfString = value?.takeUnretainedValue() else { return nil }
    return cfString as String
}

private func findAudioDeviceID(uid: String) -> AudioDeviceID? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize
    )
    guard status == noErr else { return nil }

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize,
        &deviceIDs
    )
    guard status == noErr else { return nil }

    for deviceID in deviceIDs {
        if let deviceUID = getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID),
           deviceUID == uid {
            return deviceID
        }
    }
    return nil
}

private func defaultOutputDeviceID() -> AudioDeviceID? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID: AudioDeviceID = 0
    var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize,
        &deviceID
    )
    guard status == noErr else { return nil }
    return deviceID
}

private func deviceName(for deviceID: AudioDeviceID) -> String? {
    getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceNameCFString)
}

private func deviceUID(for deviceID: AudioDeviceID) -> String? {
    getStringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
}

private func nominalSampleRate(for deviceID: AudioDeviceID) -> Float64? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var sampleRate: Float64 = 0
    var dataSize = UInt32(MemoryLayout<Float64>.size)
    let status = AudioObjectGetPropertyData(
        deviceID,
        &propertyAddress,
        0, nil,
        &dataSize,
        &sampleRate
    )
    guard status == noErr else { return nil }
    return sampleRate
}

private func setNominalSampleRate(for deviceID: AudioDeviceID, rate: Float64) -> Bool {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var settable: DarwinBoolean = false
    let settableStatus = AudioObjectIsPropertySettable(deviceID, &propertyAddress, &settable)
    guard settableStatus == noErr, settable.boolValue else {
        log("ERROR: Sample rate is not settable on this device")
        return false
    }

    var rate = rate
    let status = AudioObjectSetPropertyData(
        deviceID,
        &propertyAddress,
        0, nil,
        UInt32(MemoryLayout<Float64>.size),
        &rate
    )

    if status != noErr {
        log("ERROR: Failed to set sample rate (OSStatus: \(status))")
        return false
    }
    return true
}

private func supportedSampleRates(for deviceID: AudioDeviceID) -> [AudioValueRange]? {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
    guard status == noErr else { return nil }

    let rangeCount = Int(dataSize) / MemoryLayout<AudioValueRange>.size
    var ranges = [AudioValueRange](repeating: AudioValueRange(), count: rangeCount)
    status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &ranges)
    guard status == noErr else { return nil }
    return ranges
}

private func deviceSupportsRate(_ deviceID: AudioDeviceID, rate: Float64) -> Bool {
    guard let ranges = supportedSampleRates(for: deviceID) else { return false }
    return ranges.contains { rate >= $0.mMinimum && rate <= $0.mMaximum }
}

/// Normalizes common sample rate misreportings (e.g., 44000 -> 44100)
private func normalizeSampleRate(_ rate: Int) -> Int {
    switch rate {
    case 44000: return 44100
    case 88000: return 88200
    case 176000: return 176400
    case 352000: return 352800
    case 705000: return 705600
    default: return rate
    }
}

// MARK: - Logging

private func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    print("[\(timestamp)] \(message)")
    fflush(stdout)
}

// MARK: - List Devices Command

private func listAudioOutputDevices() {
    var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize
    )
    guard status == noErr else {
        print("Error: Could not enumerate audio devices")
        return
    }

    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0, nil,
        &dataSize,
        &deviceIDs
    )
    guard status == noErr else {
        print("Error: Could not get audio device list")
        return
    }

    print("Audio Output Devices:")
    print(String(repeating: "-", count: 80))

    for deviceID in deviceIDs {
        var outputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var outputSize: UInt32 = 0
        let outputStatus = AudioObjectGetPropertyDataSize(deviceID, &outputAddress, 0, nil, &outputSize)
        guard outputStatus == noErr, outputSize > 0 else { continue }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        var bufSize = outputSize
        let bufStatus = AudioObjectGetPropertyData(deviceID, &outputAddress, 0, nil, &bufSize, bufferListPointer)
        guard bufStatus == noErr else { continue }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let outputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard outputChannels > 0 else { continue }

        let name = deviceName(for: deviceID) ?? "Unknown"
        let uid = deviceUID(for: deviceID) ?? "Unknown"
        let rate = nominalSampleRate(for: deviceID).map { "\(Int($0)) Hz" } ?? "Unknown"
        let rates = supportedSampleRates(for: deviceID)?
            .map { range in
                if range.mMinimum == range.mMaximum {
                    return "\(Int(range.mMinimum))"
                } else {
                    return "\(Int(range.mMinimum))-\(Int(range.mMaximum))"
                }
            }
            .joined(separator: ", ") ?? "Unknown"

        print("  Name:             \(name)")
        print("  UID:              \(uid)")
        print("  Current Rate:     \(rate)")
        print("  Supported Rates:  \(rates)")
        print(String(repeating: "-", count: 80))
    }
}

// MARK: - Sample Rate Switcher Daemon

@MainActor
final class SampleRateSwitcher {
    private let targetDeviceID: AudioDeviceID
    private let targetDeviceName: String
    private let pauseDuringSwitch: Bool
    private var lastSwitchedRate: Float64 = 0
    private var logProcess: Process?
    private var logMonitor: LogMonitor?
    private var lastLogRate: Int?
    private var playbackStartTime: CFAbsoluteTime?
    private var currentTrackID: String?
    private var currentTrackState: String?
    private var lastHandledRate: Int?
    private var lastLoggedLogRate: Int?
    private var detectionWinner: String?
    private var maxRateForCurrentTrack: Int = 0
    private var logDebounceTask: Task<Void, Never>?
    private var isPausedForSwitch: Bool = false
    private var pendingResumeTask: Task<Void, Never>?
    private var lastResumeTime: CFAbsoluteTime = 0
    private var trackRateCache: [String: Int] = [:] // Cache of trackID -> sample rate
    
    // Pre-compiled AppleScript for faster execution (~16ms vs ~46ms per call)
    private let pauseScript: NSAppleScript? = {
        let script = NSAppleScript(source: "tell application \"Music\" to pause")
        script?.compileAndReturnError(nil)
        return script
    }()
    private let playScript: NSAppleScript? = {
        let script = NSAppleScript(source: "tell application \"Music\" to play")
        script?.compileAndReturnError(nil)
        return script
    }()

    init(deviceID: AudioDeviceID, pauseDuringSwitch: Bool = false) {
        self.targetDeviceID = deviceID
        self.targetDeviceName = deviceName(for: deviceID) ?? "Unknown"
        self.pauseDuringSwitch = pauseDuringSwitch
        self.logMonitor = LogMonitor { [weak self] rate in
            Task { @MainActor in
                self?.handleLogRateUpdate(rate)
            }
        }
    }

    func start() {
        logMonitor?.start()

        let currentRate = nominalSampleRate(for: targetDeviceID) ?? 0
        log("Monitoring Apple Music for sample rate changes")
        log("Target DAC: \(targetDeviceName) (current rate: \(Int(currentRate)) Hz)")

        if let rates = supportedSampleRates(for: targetDeviceID) {
            let rateStrings = rates.map { range in
                if range.mMinimum == range.mMaximum {
                    return "\(Int(range.mMinimum)) Hz"
                } else {
                    return "\(Int(range.mMinimum))-\(Int(range.mMaximum)) Hz"
                }
            }
            log("Supported sample rates: \(rateStrings.joined(separator: ", "))")
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handlePlayerNotification(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        log("Listening for playback events... (press Ctrl+C to stop)")
    }


    @objc private func handlePlayerNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let state = info["Player State"] as? String ?? "Unknown"
        let trackName = info["Name"] as? String ?? "Unknown"
        let artist = info["Artist"] as? String ?? "Unknown"
        let album = info["Album"] as? String ?? "Unknown"
        let trackID = "\(trackName)-\(artist)-\(album)"
        
        // Skip redundant notifications
        if trackID == currentTrackID && state == currentTrackState {
            return
        }
        
        let isNewTrack = trackID != currentTrackID
        let isPlayStart = state == "Playing" && currentTrackState != "Playing"

        currentTrackID = trackID
        currentTrackState = state

        log("Player state: \(state) — \(trackName) by \(artist)")

        if state == "Playing" {
            let now = CFAbsoluteTimeGetCurrent()
            
            // Ignore "Playing" notifications that occur within 2 seconds of our resume
            // These are triggered by our own resumePlayback() call, but due to async timing
            // and notification delivery delays, we need a generous window
            if (now - lastResumeTime) < 2.0 {
                return
            }
            
            if isNewTrack || isPlayStart {
                playbackStartTime = now
                // Reset state when a new track starts
                lastLogRate = nil
                lastHandledRate = nil
                lastLoggedLogRate = nil
                detectionWinner = nil
                maxRateForCurrentTrack = 0
                logDebounceTask?.cancel()
                logDebounceTask = nil
                pendingResumeTask?.cancel()
                pendingResumeTask = nil
                isPausedForSwitch = false
                
                // If pause-during-switch is enabled, pause immediately
                if pauseDuringSwitch {
                    // Check cache first — if we've seen this track before, switch instantly
                    if let cachedRate = trackRateCache[trackID] {
                        let currentRate = nominalSampleRate(for: targetDeviceID) ?? 0
                        if Double(cachedRate) != currentRate {
                            pausePlayback()
                            isPausedForSwitch = true
                            log("Paused playback for cached rate switch...")
                            Task {
                                await switchToRate(cachedRate, startTime: now, source: "Cache")
                            }
                        } else {
                            log("DAC already at cached rate \(cachedRate) Hz — no pause needed")
                        }
                    } else {
                        pausePlayback()
                        isPausedForSwitch = true
                        log("Paused playback for sample rate detection...")
                    }
                }
            }
            
            // Log stream will handle sample rate detection
        } else if state == "Stopped" {
            // Reset state on stop to avoid carrying over max rate to next track if it's detected via log early
            playbackStartTime = nil
            lastHandledRate = nil
            lastLoggedLogRate = nil
            maxRateForCurrentTrack = 0
            currentTrackID = nil
            isPausedForSwitch = false
            pendingResumeTask?.cancel()
        } else {
            // Paused - but only reset if we didn't pause it ourselves
            if !isPausedForSwitch {
                playbackStartTime = nil
                lastHandledRate = nil
                lastLoggedLogRate = nil
            }
        }
    }

    private func handleLogRateUpdate(_ rate: Int) {
        lastLogRate = rate
        
        // Update max rate for current track
        if rate > maxRateForCurrentTrack {
            maxRateForCurrentTrack = rate
        }
        
        // Debounce log updates: wait 30ms and use the highest rate seen
        // (reduced from 100ms — log lines arrive in rapid bursts)
        logDebounceTask?.cancel()
        logDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms
            if Task.isCancelled { return }
            
            let bestRate = self.maxRateForCurrentTrack
            
            // If we already handled this rate for the current playback session, skip
            if let lastHandled = self.lastHandledRate, lastHandled == bestRate {
                return
            }
            
            // Deduplicate logging of the same detected rate
            if self.lastLoggedLogRate != bestRate {
                // log("Log stream detected sample rate: \(bestRate) Hz")
                self.lastLoggedLogRate = bestRate
            }
            
            // If we are currently playing, check if we need to switch
            let currentRate = nominalSampleRate(for: self.targetDeviceID) ?? 0
            if Double(bestRate) != currentRate {
                if self.detectionWinner == nil {
                    self.detectionWinner = "Real-time Log Stream"
                }
                await self.switchToRate(bestRate, startTime: self.playbackStartTime, source: "Log Stream")
            }
            
            // Cache the rate for this track for instant switching on repeat plays
            if let trackID = self.currentTrackID {
                self.trackRateCache[trackID] = bestRate
            }
        }
    }


    private func switchToRate(_ trackRate: Int, startTime: CFAbsoluteTime? = nil, source: String = "Unknown") async {
        let trackRateFloat = Float64(trackRate)
        
        guard let currentDACRate = nominalSampleRate(for: targetDeviceID) else {
            log("ERROR: Could not read current DAC sample rate")
            // Resume playback if we paused it (can't proceed without DAC rate)
            resumeIfPaused()
            return
        }

        if trackRateFloat == currentDACRate {
            if lastHandledRate != trackRate {
                log("DAC already at \(Int(currentDACRate)) Hz — no switch needed (Source: \(source))")
                lastHandledRate = trackRate
                // Resume playback if we paused it (no switch needed)
                resumeIfPaused()
            }
            return
        }

        guard deviceSupportsRate(targetDeviceID, rate: trackRateFloat) else {
            if lastHandledRate != trackRate {
                log("WARNING: DAC does not support \(trackRate) Hz — keeping \(Int(currentDACRate)) Hz (Source: \(source))")
                lastHandledRate = trackRate
                // Resume playback if we paused it (can't switch to unsupported rate)
                resumeIfPaused()
            }
            return
        }
        
        // Prevent redundant switching if another task already initiated the same rate switch
        if lastHandledRate == trackRate {
            return
        }
        lastHandledRate = trackRate

        log("Switching DAC from \(Int(currentDACRate)) Hz to \(trackRate) Hz... (Source: \(source))")

        let switchStartTime = CFAbsoluteTimeGetCurrent()
        if setNominalSampleRate(for: targetDeviceID, rate: trackRateFloat) {
            let now = CFAbsoluteTimeGetCurrent()
            let switchElapsed = (now - switchStartTime) * 1000
            
            if let start = startTime {
                let totalElapsed = (now - start) * 1000
                log("SUCCESS: DAC set to \(trackRate) Hz (switch took \(String(format: "%.1f", switchElapsed)) ms, detected at +\(String(format: "%.1f", totalElapsed)) ms) (Source: \(source))")
            } else {
                log("SUCCESS: DAC set to \(trackRate) Hz (switch took \(String(format: "%.1f", switchElapsed)) ms) (Source: \(source))")
            }
            lastSwitchedRate = trackRateFloat
            
            
            // Resume playback if we paused it
            resumeIfPaused()
        } else {
            log("FAILED: Could not set DAC to \(trackRate) Hz")
            // Still resume even if switch failed
            resumeIfPaused()
        }
    }


    private func pausePlayback() {
        var errorInfo: NSDictionary?
        pauseScript?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            log("AppleScript pause error: \(error)")
        }
    }
    
    private func resumePlayback() {
        var errorInfo: NSDictionary?
        playScript?.executeAndReturnError(&errorInfo)
        if let error = errorInfo {
            log("AppleScript resume error: \(error)")
        }
    }
    
    private func resumeIfPaused() {
        guard isPausedForSwitch else { return }
        isPausedForSwitch = false
        
        // Set lastResumeTime synchronously to avoid race with notification handler
        self.lastResumeTime = CFAbsoluteTimeGetCurrent()
        // Minimal delay to let DAC settle before resuming
        pendingResumeTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            if Task.isCancelled { return }
            self.lastResumeTime = CFAbsoluteTimeGetCurrent()
            resumePlayback()
            log("Resumed playback after DAC switch")
        }
    }

}

// MARK: - Log Monitor

final class LogMonitor {
    private let callback: (Int) -> Void
    private var process: Process?
    
    init(callback: @escaping (Int) -> Void) {
        self.callback = callback
    }
    
    func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        let predicates = [
            "process == \"Music\" AND message CONTAINS \"activeFormat\"",
            "process == \"Music\" AND message CONTAINS \"subaq_buildCAAudioQueue\"",
            "process == \"Music\" AND message CONTAINS \"FigStreamPlayer\"",
            "process == \"Music\" AND message CONTAINS \"asbdSampleRate\""
        ].joined(separator: " OR ")
        
        process.arguments = ["stream", "--predicate", predicates, "--style", "compact"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                var detectedRate: Int? = nil
                
                if line.contains("sampleRate:") {
                    let parts = line.components(separatedBy: "sampleRate:")
                    if parts.count > 1 {
                        let ratePart = parts[1].trimmingCharacters(in: .whitespaces)
                        let rateStr = ratePart.prefix(while: { $0.isNumber || $0 == "." })
                        if let rate = Double(rateStr) {
                            detectedRate = rate < 1000 ? Int(rate * 1000) : Int(rate)
                        }
                    }
                } else if line.contains("SampleRate ") {
                    // Handle formats like [SampleRate 96000]
                    let parts = line.components(separatedBy: "SampleRate ")
                    if parts.count > 1 {
                        let ratePart = parts[1].trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
                        if let rate = Int(ratePart) {
                            detectedRate = rate
                        }
                    }
                } else if line.contains("asbdSampleRate = ") {
                    // Handle formats like asbdSampleRate = 44.1 kHz
                    let parts = line.components(separatedBy: "asbdSampleRate = ")
                    if parts.count > 1 {
                        let ratePart = parts[1].trimmingCharacters(in: .whitespaces)
                        let rateStr = ratePart.prefix(while: { $0.isNumber || $0 == "." })
                        if let rate = Double(rateStr) {
                            detectedRate = rate < 1000 ? Int(rate * 1000) : Int(rate)
                        }
                    }
                }
                
                if let rate = detectedRate {
                    self?.callback(normalizeSampleRate(rate))
                }
            }
        }
        
        do {
            try process.run()
            self.process = process
        } catch {
            print("ERROR: Failed to start log stream: \(error)")
        }
    }
    
    func stop() {
        process?.terminate()
    }
}

// MARK: - CLI

private func printUsage() {
    print("""
    Apple Music Sample Rate Switcher
    
    Automatically switches your DAC's sample rate to match the current
    Apple Music track's native sample rate when playback starts.
    
    USAGE:
        AppleMusicSampleRateSwitcher [OPTIONS]
    
    OPTIONS:
        --list-devices        List all audio output devices and their UIDs
        --device-uid <UID>    Specify the target DAC by its UID
                              (default: system default output device)
        --pause-during-switch Pause playback while switching DAC sample rate,
                              then auto-resume. Eliminates audio glitches.
        --help                Show this help message
    
    EXAMPLES:
        # List available audio devices to find your DAC's UID:
        AppleMusicSampleRateSwitcher --list-devices
    
        # Run with the default output device:
        AppleMusicSampleRateSwitcher
    
        # Run with a specific DAC:
        AppleMusicSampleRateSwitcher --device-uid "AppleUSBAudioEngine:Schiit Audio:Modi:001"
    
        # Run with pause-during-switch for gapless switching:
        AppleMusicSampleRateSwitcher --device-uid "YOUR_DAC_UID" --pause-during-switch
    """)
}

// MARK: - App Main

private var globalSwitcher: SampleRateSwitcher?

@MainActor
func run() async {
    // Parse arguments
    let args = CommandLine.arguments

    if args.contains("--help") || args.contains("-h") {
        printUsage()
        exit(0)
    }

    if args.contains("--list-devices") {
        listAudioOutputDevices()
        exit(0)
    }

    let pauseDuringSwitch = args.contains("--pause-during-switch")
    let deviceID: AudioDeviceID

    if let uidIndex = args.firstIndex(of: "--device-uid"), uidIndex + 1 < args.count {
        let uid = args[uidIndex + 1]
        guard let id = findAudioDeviceID(uid: uid) else {
            print("Error: No audio device found with UID '\(uid)'")
            print("Run with --list-devices to see available devices.")
            exit(1)
        }
        deviceID = id
        log("Using device: \(deviceName(for: id) ?? uid)")
    } else {
        guard let id = defaultOutputDeviceID() else {
            print("Error: Could not determine default output device")
            exit(1)
        }
        deviceID = id
        log("Using default output device: \(deviceName(for: id) ?? "Unknown")")
    }

    if pauseDuringSwitch {
        log("Pause-during-switch mode ENABLED: Playback will pause during DAC rate changes")
    }

    // Handle SIGINT gracefully
    signal(SIGINT) { _ in
        print("\n[\(Date())] Shutting down...")
        exit(0)
    }

    globalSwitcher = SampleRateSwitcher(deviceID: deviceID, pauseDuringSwitch: pauseDuringSwitch)
    globalSwitcher?.start()
}

Task { @MainActor in
    await run()
}

RunLoop.main.run()
