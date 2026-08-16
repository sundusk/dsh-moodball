// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MoodBall",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MoodBall",
            path: "Sources/MoodBall"
        )
    ]
)
