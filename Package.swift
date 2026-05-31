// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Footswitch",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FootswitchCore"),
        .executableTarget(
            name: "Footswitch",
            dependencies: ["FootswitchCore"],
            // Info.plist is not allowed as a top-level processed resource by SwiftPM.
            // It is kept in Resources/ for the eventual .app bundle packaging step and
            // excluded from the resource bundle here.
            exclude: ["Resources/Info.plist"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FootswitchCoreTests",
            dependencies: ["FootswitchCore"]
        ),
    ]
)
