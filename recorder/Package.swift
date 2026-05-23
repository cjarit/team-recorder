// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "recorder",
    platforms: [
        .macOS(.v13)   // ScreenCaptureKit audio requires macOS 13+
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
