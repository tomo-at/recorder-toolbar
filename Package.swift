// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RecorderToolbar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RecorderToolbar",
            path: "Sources/RecorderToolbar"
        )
    ]
)
