// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "recorder",
    platforms: [
        .macOS(.v15)   // macOS 15+ Sequoia — minimum supported OS for public release
    ],
    targets: [
        .executableTarget(
            name: "recorder",
            path: "Sources/recorder",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
