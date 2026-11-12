// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Loopsmith",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Loopsmith"),
        .testTarget(name: "LoopsmithTests", dependencies: ["Loopsmith"]),
    ]
)
