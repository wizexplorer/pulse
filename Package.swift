// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v14)],
    targets: [
        // Tiny Objective-C shim: Swift cannot catch NSExceptions, and a few AppKit
        // getters (NSTouch.normalizedPosition) can raise them.
        .target(name: "PulseObjC", path: "Sources/PulseObjC"),
        .executableTarget(
            name: "Pulse",
            dependencies: ["PulseObjC"],
            path: "Sources/Pulse",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
