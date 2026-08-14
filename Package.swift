// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Waterball",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Waterball",
            path: "Sources/Waterball"
        )
    ]
)
