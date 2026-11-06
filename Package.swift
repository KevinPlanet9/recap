// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Recap",
    platforms: [.macOS(.v26)],
    dependencies: [
        // In-app updates: the one third-party dependency, pinned to an exact version.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Transcript model, line building, search, exports and saved transcripts. No UI, so it is easy to test.
        .target(name: "RecapCore", path: "Sources/RecapCore"),
        // The Mac app: window, speech engine, playback, in-app updates, and the command line modes used by the checks.
        .executableTarget(name: "Recap", dependencies: ["RecapCore", .product(name: "Sparkle", package: "Sparkle")],
                          path: "Sources/Recap"),
        .testTarget(name: "RecapCoreTests", dependencies: ["RecapCore"], path: "Tests/RecapCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
