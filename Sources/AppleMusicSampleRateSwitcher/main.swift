import Foundation
import CoreAudio
import AudioToolbox
#if canImport(MusicKit)
import MusicKit
#endif

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

final class SampleRateSwitcher {
    private let targetDeviceID: AudioDeviceID
    private let targetDeviceName: String
    private var lastSwitchedRate: Float64 = 0
    private var logProcess: Process?
    private var rateCache: [String: Int] = [:]
    private var logMonitor: LogMonitor?
    private var lastLogRate: Int?

    init(deviceID: AudioDeviceID) {
        self.targetDeviceID = deviceID
        self.targetDeviceName = deviceName(for: deviceID) ?? "Unknown"
        self.logMonitor = LogMonitor { [weak self] rate in
            self?.handleLogRateUpdate(rate)
        }
    }

    func start() {
        logMonitor?.start()
        #if canImport(MusicKit)
        Task {
            let status = MusicAuthorization.currentStatus
            if status != .authorized {
                log("INFO: MusicKit library access is \(status). This is expected if you haven't granted 'Media & Apple Music' permission. Catalog-only lookups will be used.")
                
                // Only request if not determined yet
                if status == .notDetermined {
                    log("Requesting MusicKit authorization...")
                    let newStatus = await MusicAuthorization.request()
                    log("MusicKit authorization status: \(newStatus)")
                    if newStatus != .authorized {
                        log("TIP: To manually grant permission, go to System Settings > Privacy & Security > Media & Apple Music.")
                        log("Or run: tccutil reset MediaLibrary com.brucew.AppleMusicSampleRateSwitcher")
                    }
                }
            } else {
                log("SUCCESS: MusicKit authorized")
            }
        }
        #endif

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
            object: nil
        )

        log("Listening for playback events... (press Ctrl+C to stop)")
        RunLoop.main.run()
    }

    private func findTrueSampleRateFromLogs() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["show", "--predicate", "process == \"Music\" AND message CONTAINS \"activeFormat\"", "--last", "2s", "--info", "--style", "compact"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            let lines = output.components(separatedBy: .newlines).reversed()
            for line in lines {
                if line.contains("sampleRate:") {
                    let parts = line.components(separatedBy: "sampleRate:")
                    if parts.count > 1 {
                        let ratePart = parts[1].trimmingCharacters(in: .whitespaces)
                        let rateStr = ratePart.prefix(while: { $0.isNumber || $0 == "." })
                        if let rate = Double(rateStr) {
                            // The log might say "48khz" or "48000" or just "48". 
                            // Usually "48khz" or "44.1khz".
                            let rawRate = rate < 1000 ? Int(rate * 1000) : Int(rate)
                            return normalizeSampleRate(rawRate)
                        }
                    }
                }
            }
        } catch {
            log("ERROR: Failed to run log command: \(error)")
        }
        
        return nil
    }

    @objc private func handlePlayerNotification(_ notification: Notification) {
        guard let info = notification.userInfo else { return }

        let state = info["Player State"] as? String ?? "Unknown"
        let trackName = info["Name"] as? String ?? "Unknown"
        let artist = info["Artist"] as? String ?? "Unknown"
        let storefrontID = info["Storefront-Item-ID"] as? String

        log("Player state: \(state) — \(trackName) by \(artist)")

        if state == "Playing" {
            // Reset last log rate when a new track starts
            lastLogRate = nil
            Task {
                await processTrackChange(info: info, storefrontID: storefrontID)
            }
        }
    }

    private func handleLogRateUpdate(_ rate: Int) {
        log("Log stream detected sample rate: \(rate) Hz")
        lastLogRate = rate
        
        // If we are currently playing, check if we need to switch
        let currentRate = nominalSampleRate(for: targetDeviceID) ?? 0
        if Double(rate) != currentRate {
            log("Log stream suggests a switch to \(rate) Hz is needed...")
            Task {
                await switchToRate(rate)
            }
        }
    }

    private func processTrackChange(info: [AnyHashable: Any], storefrontID: String?) async {
        let startTime = CFAbsoluteTimeGetCurrent()

        var trackRate = queryTrackSampleRate() ?? 0
        
        // Try MusicKit if we have a storefront ID
        if let sid = storefrontID {
            #if canImport(MusicKit)
            if let mkRate = await queryMusicKitSampleRate(storefrontID: sid) {
                // If MusicKit suggests a higher rate than AppleScript (which often defaults to 44.1k for streams), use it
                if trackRate <= 44100 && mkRate > 44100 {
                    log("MusicKit-detected native sample rate: \(mkRate) Hz (AppleScript reported \(trackRate) Hz)")
                    trackRate = mkRate
                }
            }
            #endif
        }

        // Check if log monitor already has a rate for us (sometimes it's faster than the notification processing)
        if let lrate = lastLogRate, lrate > 44100 && trackRate <= 44100 {
            log("Log monitor already detected higher rate: \(lrate) Hz")
            trackRate = lrate
        }

        if trackRate == 0 {
            log("WARNING: Could not determine track sample rate from AppleScript or MusicKit")
            
            // Fallback to slow logs if log monitor hasn't caught it yet
            if let logRate = findTrueSampleRateFromLogs() {
                log("Log-detected native sample rate: \(logRate) Hz")
                trackRate = logRate
            }
        }
        
        if trackRate == 0 {
            return
        }

        await switchToRate(trackRate, startTime: startTime)
    }

    private func switchToRate(_ trackRate: Int, startTime: CFAbsoluteTime? = nil) async {
        let trackRateFloat = Float64(trackRate)
        
        guard let currentDACRate = nominalSampleRate(for: targetDeviceID) else {
            log("ERROR: Could not read current DAC sample rate")
            return
        }

        if trackRateFloat == currentDACRate {
            log("DAC already at \(Int(currentDACRate)) Hz — no switch needed")
            return
        }

        guard deviceSupportsRate(targetDeviceID, rate: trackRateFloat) else {
            log("WARNING: DAC does not support \(trackRate) Hz — keeping \(Int(currentDACRate)) Hz")
            return
        }

        log("Switching DAC from \(Int(currentDACRate)) Hz to \(trackRate) Hz...")

        if setNominalSampleRate(for: targetDeviceID, rate: trackRateFloat) {
            if let start = startTime {
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                log("SUCCESS: DAC set to \(trackRate) Hz (took \(String(format: "%.1f", elapsed)) ms)")
            } else {
                log("SUCCESS: DAC set to \(trackRate) Hz")
            }
            lastSwitchedRate = trackRateFloat
        } else {
            log("FAILED: Could not set DAC to \(trackRate) Hz")
        }
    }

    private func queryMusicKitSampleRate(storefrontID: String) async -> Int? {
        if let cached = rateCache[storefrontID] {
            return cached
        }

        #if canImport(MusicKit)
        if MusicAuthorization.currentStatus == .authorized {
            do {
                // First, try the standard Song request which is faster
                var rate: Int? = nil
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(storefrontID))
                if let response = try? await request.response(), let song = response.items.first {
                    // Map variants to reasonable defaults if we can't get exact info
                    if let variants = song.audioVariants {
                        if variants.contains(.highResolutionLossless) {
                            rate = 96000
                        } else if variants.contains(.lossless) {
                            rate = 48000
                        }
                    }
                }
                
                // Attempt to get exact metadata via the raw data request
                var storefront = "us"
                if let s = try? await MusicDataRequest.currentCountryCode {
                    storefront = s
                }
                let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/songs/\(storefrontID)?extend=extended-attributes")!
                let dataRequest = MusicDataRequest(urlRequest: URLRequest(url: url))
                let dataResponse = try await dataRequest.response()
                
                if let json = try? JSONSerialization.jsonObject(with: dataResponse.data) as? [String: Any],
                   let data = json["data"] as? [[String: Any]],
                   let songData = data.first,
                   let attributes = songData["attributes"] as? [String: Any],
                   let extended = attributes["extendedAttributes"] as? [String: Any],
                   let audioAttrs = extended["audioAttributes"] as? [[String: Any]] {
                    
                    let maxRate = audioAttrs.compactMap { $0["sampleRate"] as? Int }.max()
                    if let r = maxRate, r > 0 {
                        let normalizedRate = normalizeSampleRate(r)
                        log("MusicKit API reported exact sample rate: \(normalizedRate) Hz")
                        rate = normalizedRate
                    }
                }
                
                if let r = rate {
                    rateCache[storefrontID] = r
                    return r
                }
            } catch {
                log("MusicKit error: \(error)")
            }
        }
        #endif

        // Fallback to public iTunes Search API if MusicKit is unauthorized or fails
        return await queryiTunesLookupSampleRate(storefrontID: storefrontID)
    }

    private func queryiTunesLookupSampleRate(storefrontID: String) async -> Int? {
        // The iTunes lookup API doesn't give sample rate, but it can confirm if it's a 'Hi-Res' track 
        // by looking at the collection name or other hints, though it's limited.
        // Actually, the best way to get it if MusicKit fails is to rely on the log monitor.
        // But we can at least try to see if there are any hints.
        
        let url = URL(string: "https://itunes.apple.com/lookup?id=\(storefrontID)")!
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let track = results.first {
                
                // Some tracks have indicators in their names or collections
                let name = (track["trackName"] as? String ?? "").lowercased()
                let collection = (track["collectionName"] as? String ?? "").lowercased()
                
                if name.contains("remastered") || collection.contains("remastered") {
                    // Remastered often means 48k+ but not always.
                    // This is just a hint. The log monitor is the real source of truth.
                }
            }
        } catch {
            log("iTunes Lookup error: \(error)")
        }
        return nil
    }

    private func queryTrackSampleRate() -> Int? {
        let script = NSAppleScript(source: """
            tell application "Music"
                try
                    return sample rate of current track
                on error
                    return -1
                end try
            end tell
        """)
        var errorInfo: NSDictionary?
        let result = script?.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            log("AppleScript error: \(error)")
            return nil
        }

        let rate = Int(result?.int32Value ?? -1)
        return rate > 0 ? normalizeSampleRate(rate) : nil
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
        process.arguments = ["stream", "--predicate", "process == \"Music\" AND message CONTAINS \"activeFormat\"", "--style", "compact"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("sampleRate:") {
                    let parts = line.components(separatedBy: "sampleRate:")
                    if parts.count > 1 {
                        let ratePart = parts[1].trimmingCharacters(in: .whitespaces)
                        let rateStr = ratePart.prefix(while: { $0.isNumber || $0 == "." })
                        if let rate = Double(rateStr) {
                            let finalRate: Int
                            if rate < 1000 {
                                finalRate = Int(rate * 1000)
                            } else {
                                finalRate = Int(rate)
                            }
                            self?.callback(normalizeSampleRate(finalRate))
                        }
                    }
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
        AppleMusicSampleRateSwitcher [--device-uid <UID>] [--list-devices]
    
    OPTIONS:
        --list-devices    List all audio output devices and their UIDs
        --device-uid <UID>  Specify the target DAC by its UID
                            (default: system default output device)
        --help            Show this help message
    
    EXAMPLES:
        # List available audio devices to find your DAC's UID:
        AppleMusicSampleRateSwitcher --list-devices
    
        # Run with the default output device:
        AppleMusicSampleRateSwitcher
    
        # Run with a specific DAC:
        AppleMusicSampleRateSwitcher --device-uid "AppleUSBAudioEngine:Schiit Audio:Modi:001"
    """)
}

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

// Handle SIGINT gracefully
signal(SIGINT) { _ in
    log("Shutting down...")
    exit(0)
}

let switcher = SampleRateSwitcher(deviceID: deviceID)
switcher.start()
