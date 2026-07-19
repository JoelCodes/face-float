// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FaceFloat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FaceFloat", path: "Sources/FaceFloat")
    ]
)
