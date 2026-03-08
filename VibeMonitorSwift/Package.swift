// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VibeMonitor",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "VibeMonitor",
            path: ".",
            exclude: ["Package.swift", "Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
