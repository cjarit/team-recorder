// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TeamRecorderBar",
    platforms: [
        .macOS(.v13)   // macOS 13+ — matches recorder binary requirement
    ],
    targets: [
        .executableTarget(
            name: "TeamRecorderBar",
            path: "Sources/TeamRecorderBar"
        )
    ]
)
