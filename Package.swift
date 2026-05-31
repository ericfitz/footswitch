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
            // Info.plist, AppIcon.icns, and the .lproj localizations are bundle
            // artifacts, not SwiftPM resources — the packaging scripts copy them
            // into the .app's Contents/ directly. Exclude them from the SwiftPM
            // resource bundle.
            exclude: ["Resources/Info.plist", "Resources/AppIcon.icns", "Resources/Localizations"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FootswitchCoreTests",
            dependencies: ["FootswitchCore"]
        ),
    ]
)
