// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppleMusicSampleRateSwitcher",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AppleMusicSampleRateSwitcher",
            path: "Sources/AppleMusicSampleRateSwitcher",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"])
            ]
        )
    ]
)
