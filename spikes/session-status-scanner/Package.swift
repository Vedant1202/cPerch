// swift-tools-version: 5.10
import PackageDescription

// cPerch — Swift Package.
// CPerchScan is a CLI spike that validates the session-status heuristic against
// real ~/.claude data (and proves the CLT + SwiftPM toolchain end to end).
// The menu-bar app proper will be added as a separate target once the heuristic
// is confirmed; the scanner logic here becomes the core CPerchCore module.
let package = Package(
    name: "cPerch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CPerchScan", path: "Sources/CPerchScan")
    ]
)
