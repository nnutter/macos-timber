// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Timber",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure model logic (filter, items, argv), no UI/process deps.
        .target(
            name: "TimberModel",
            path: "Sources/TimberModel"
        ),
        // SwiftUI menubar frontend to the `timber` CLI.
        // Requires an Xcode toolchain (SwiftUI macros).
        .executableTarget(
            name: "Timber",
            dependencies: ["TimberModel"],
            path: "Sources/Timber",
            exclude: ["Artwork"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TimberModelTests",
            dependencies: ["TimberModel"],
            path: "Tests/TimberModelTests"
        ),
    ]
)
