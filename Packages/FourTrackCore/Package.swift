// swift-tools-version:5.10
import PackageDescription

// Platform-independent core for Four-Track: data model, project store,
// audio file I/O, splicing, macro curves, waveform peaks and the offline
// Cleanup DSP. Nothing here imports AVFoundation or SwiftUI, so the whole
// package builds and tests on Linux as well as on Apple platforms.
let package = Package(
    name: "FourTrackCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FourTrackCore", targets: ["FourTrackCore"]),
    ],
    targets: [
        .target(
            name: "CRNNoise",
            path: "Sources/CRNNoise",
            exclude: ["LICENSE"],
            cSettings: [
                .define("RNNOISE_BUILD"),
            ]
        ),
        .target(
            name: "FourTrackCore",
            dependencies: ["CRNNoise"],
            path: "Sources/FourTrackCore",
            resources: [.copy("Resources/Drums")]
        ),
        .testTarget(
            name: "FourTrackCoreTests",
            dependencies: ["FourTrackCore"],
            path: "Tests/FourTrackCoreTests"
        ),
    ]
)
