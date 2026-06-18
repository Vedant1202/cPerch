// swift-tools-version: 6.0
import PackageDescription

// cPerch — focused, Claude-native menu-bar session monitor.
// Targets: CPerchCore (pure, Foundation-only, unit-tested with swift-testing) +
// CPerchApp (AppKit + SwiftUI). Builds with Command Line Tools + SwiftPM (no full Xcode).
// tools-version 6.0 is required for swift-testing integration; the Swift language mode is
// pinned to v5 for now to avoid strict-concurrency churn in the AppKit code (adopt 6 later).
let package = Package(
    name: "cPerch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CPerchCore"),
        .executableTarget(
            name: "CPerchApp",
            dependencies: ["CPerchCore"]
        ),
        .testTarget(
            name: "CPerchCoreTests",
            dependencies: ["CPerchCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
