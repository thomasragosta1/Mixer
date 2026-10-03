# Four-Track

A native iOS multitrack recorder that feels like Voice Memos, not a DAW. It has four fixed tracks, one take per track, tape-style overwrite from any point, and a few macro sliders that always sound good. Depth sits behind a Developer Mode toggle.

- Spec: [`CLAUDE.md`](CLAUDE.md)
- Choices made where the spec left room: [`DECISIONS.md`](DECISIONS.md)

## Requirements

- Xcode 26 or later (App Store uploads require the iOS 26 SDK); the app targets iOS 17+, iPhone.
- An Apple Developer account for running on a device.

## Open and run

1. Open `FourTrack.xcodeproj`.
2. Select the **FourTrack** target → **Signing & Capabilities**, pick your team, and set your bundle identifier (placeholder: `com.fourtrack.app`).
3. Run on an iPhone. The simulator works for the UI, but recording latency and audio routes only mean something on a device.

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing files, either add them in Xcode or regenerate with:

```sh
brew install xcodegen
xcodegen generate
```

## Layout

```
FourTrack/                    iOS app (SwiftUI + AVFoundation)
  App/                        FourTrackApp, AppSettings
  Audio/                      AudioSessionManager, MixerEngine, TrackChain, Recorder,
                              Metronome, Exporter, LatencyCalibrator
  ViewModels/                 ProjectsViewModel, ProjectViewModel
  UI/                         Projects list, project view, track rows, mix strips,
                              CenteredSlider / MacroSlider / VolumeFader, export, settings
  Waveform/                   WaveformView
  Resources/                  Info.plist, assets, privacy manifest
Packages/FourTrackCore/       Platform-independent core (no AVFoundation / SwiftUI)
  Sources/FourTrackCore/      Models, ProjectStore, CAF I/O, Splicer, MacroCurves,
                              PeakGenerator, Latency, Cleanup DSP
  Sources/CRNNoise/           RNNoise v0.1.1 (BSD-3-Clause), vendored
  Tests/FourTrackCoreTests/   MacroCurves, Splicer, ProjectStore, DSP tests
```

## Tests

The core package tests run anywhere Swift runs:

```sh
cd Packages/FourTrackCore
swift test
```

In Xcode, **Product → Test** on the FourTrack scheme runs the same suite.
