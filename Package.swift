// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeFM",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudeFM", path: "Sources/ClaudeFM")
    ]
)
