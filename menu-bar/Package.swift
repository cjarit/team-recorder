// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TeamRecorderBar",
    platforms: [
        .macOS(.v14)   // macOS 14+ Sonoma — EKEventStore full-access API requires 14; SMAppService reliable from 14
    ],
    targets: [
        .executableTarget(
            name: "TeamRecorderBar",
            path: "Sources/TeamRecorderBar"
        )
    ]
)
