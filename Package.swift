// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DiscordVoiceHotkey",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DiscordVoiceHotkeyCore", targets: ["DiscordVoiceHotkeyCore"]),
    ],
    targets: [
        .target(name: "DiscordVoiceHotkeyCore"),
        .testTarget(
            name: "DiscordVoiceHotkeyCoreTests",
            dependencies: ["DiscordVoiceHotkeyCore"]
        ),
    ]
)
