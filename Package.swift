// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ISRCStamper",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BWFKit"),
        .executableTarget(
            name: "ISRCStamperApp",
            dependencies: ["BWFKit"]
        ),
        .executableTarget(name: "bwfctl", dependencies: ["BWFKit"]),
        .testTarget(name: "BWFKitTests", dependencies: ["BWFKit"]),
    ]
)
