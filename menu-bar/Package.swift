// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TeamRecorderBar",
    platforms: [
        .macOS(.v15)   // macOS 15+ Sequoia — EKEventStore full-access API requires 14; SMAppService reliable from 14
    ],
    targets: [
        .executableTarget(
            name: "TeamRecorderBar",
            path: "Sources/TeamRecorderBar"
        )
    ],
    swiftLanguageModes: [.v5]
)
