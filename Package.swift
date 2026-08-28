// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DiscordVoiceHotkey",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DiscordVoiceHotkeyCore", targets: ["DiscordVoiceHotkeyCore"]),
        .executable(name: "DiscordVoiceHotkey", targets: ["DiscordVoiceHotkey"]),
    ],
    targets: [
        .target(name: "DiscordVoiceHotkeyCore"),
        .executableTarget(
            name: "DiscordVoiceHotkey",
            dependencies: ["DiscordVoiceHotkeyCore"]
        ),
        .testTarget(
            name: "DiscordVoiceHotkeyCoreTests",
            dependencies: ["DiscordVoiceHotkeyCore"]
        ),
    ]
)
