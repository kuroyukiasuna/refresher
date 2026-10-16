// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Refresher",
    platforms: [.macOS(.v14)],
    targets: [
        // Break scheduling and meeting-detection rules. No AppKit, so it's unit-testable.
        .target(name: "RefresherCore"),
        // The menu bar app: Core Audio polling, windows, settings.
        .executableTarget(name: "Refresher", dependencies: ["RefresherCore"]),
        .testTarget(name: "RefresherCoreTests", dependencies: ["RefresherCore"]),
    ]
)
