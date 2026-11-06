// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Recap",
    platforms: [.macOS(.v26)],
    targets: [
        // Transcript model, line building, search, exports and saved transcripts. No UI, so it is easy to test.
        .target(name: "RecapCore", path: "Sources/RecapCore"),
        // The Mac app: window, speech engine, playback, and the command line modes used by the checks.
        .executableTarget(name: "Recap", dependencies: ["RecapCore"], path: "Sources/Recap"),
        .testTarget(name: "RecapCoreTests", dependencies: ["RecapCore"], path: "Tests/RecapCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
