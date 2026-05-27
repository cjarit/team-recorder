// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "recorder",
    platforms: [
        .macOS(.v14)   // macOS 14+ Sonoma — minimum supported OS for public release
    ],
    targets: [
        .executableTarget(
            name: "recorder",
            path: "Sources/recorder",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
