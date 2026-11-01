// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SecureMyMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SecureMyMac", path: "Sources/SecureMyMac"),
        .testTarget(name: "SecureMyMacTests", dependencies: ["SecureMyMac"], path: "Tests/SecureMyMacTests"),
    ]
)
