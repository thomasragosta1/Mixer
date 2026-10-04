# Decisions

Choices made where `CLAUDE.md` left room, or where the spec offered options. Each one picks the simplest option that keeps the Voice Memos feel.

## Open decisions from §13 (defaults taken, owner to confirm)

| Question | Default shipped | Where to change |
|---|---|---|
| Live cleanup at launch? | **Post-record polish only.** | `CleanupPipeline` is offline-only. |
| Minimum iPhone / iOS | **iOS 17.0**, iPhone only, portrait. No API needed iOS 18. | `project.yml` → `deploymentTarget`, `TARGETED_DEVICE_FAMILY` |
| Warmth in v1? | **First update.** The code ships behind a flag (Settings → Developer Mode → Experimental → Warmth Macro), off by default. | `AppSettings.warmthEnabled` |
| App name and icon | Display name **"Four-Track"**, placeholder icon (four waveform lanes + red playhead). | `project.yml` → `CFBundleDisplayName`; `FourTrack/Resources/Assets.xcassets/AppIcon.appiconset` |
| Bundle ID / team | Placeholder `com.fourtrack.app`, no team. | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` |

## Architecture

- **Two layers.** `Packages/FourTrackCore` is a Swift package with no AVFoundation or SwiftUI imports: data model, JSON project store, CAF reader/writer, splicer, macro curves, waveform peaks, latency math, click synthesis and the Cleanup DSP. It builds and tests on Linux and macOS. The iOS app (`FourTrack/`) holds everything that touches AVFoundation or SwiftUI. Spec file names were kept; some files from §9 live in the package (`MacroCurves`, `Splicer`, `PeakGenerator`, `DeEsser`, `CleanupProcessor`, models).
- **Persistence: Codable JSON, not SwiftData.** One `project.json` per project folder next to its audio. It's simpler, testable without a simulator, and atomic writes come free (`Data.write(options: .atomic)`). Dates are stored as seconds since 1970.
- **Track audio: hand-written CAF writer/reader** (48 kHz mono Float32 little-endian, which AVAudioFile reads natively). Owning the bytes makes the splice path, the part that must never corrupt a take, fully unit-testable. The scratch recording is written with data-chunk size `-1` until finished, so a file cut off by a crash still reads.
- **Effects run in stereo.** Files and players are mono (as specified); the per-track sub-mixer upmixes to stereo before the EQ so the reverb has width. Tracks stay centered and pan isn't exposed.
- **Master peak limiter.** Every track feeds `master mixer → Apple PeakLimiter → main mixer`. This is what guarantees "no clipping at any macro position" even with four tracks at +6 dB and maximum compressor makeup. The bounce goes through the same limiter.
- **Microphone enabled lazily.** The input node is only touched on the first recording, so opening and playing a project never turns on the mic indicator.

## Drum tracks (owner request)

- **A track is either Audio or Drums.** The + under the lanes offers "Audio Track" or "Drum Track". A drum lane shows its kit in a pill under M/S (tap it to change); Cleanup doesn't apply to drums.
- **Three synthesized kits, no samples:** Studio (acoustic-style), 808 (analog drum machine) and Hand Percussion (cajón, bongos, conga, shaker, tambourine, woodblock). Eight pads each. Each kit has its own pad colours.
- **The pad** appears above the transport whenever a drum track is armed. Pads fire on touch-down, play polyphonically through the drum track's own chain (so EQ, compressor, Space and volume apply), and give a light haptic.
- **Recording drums records hits, not the microphone.** Each hit is stored with its timeline time, shifted earlier by the output latency so it lands where the player heard it. On stop, hits in the recorded span replace the old ones (the same overwrite-anywhere rule as audio), and the whole track is rendered to its audio file. Mixing, export, mute/solo and waveforms then work exactly as for audio tracks.
- **Changing a kit re-renders every existing hit** with the new kit.

## Recording and timing

- **Alignment uses host time, not buffer counting.** Players start at a shared host time `T`. The recorder notes the host time of the first captured sample, and the splice skips `(T − firstSample + latency) × 48 kHz` frames of the scratch file. This removes tap-start jitter and pre-roll, and makes count-in work for free (the count-in audio is skipped).
- **Latency default** is the spec formula: `inputNode.presentationLatency + outputNode.presentationLatency + 2 × ioBufferDuration`. A calibrated value replaces it per route; the manual Developer Mode offset is added on top. **This still has to be verified on device** (acceptance: ≤ 5 ms on wired headphones). If takes land consistently early or late, either the formula double-counts or the tap timestamp is already compensated; run Calibrate and compare with the estimate shown in Settings.
- **Crossfades** are 5 ms equal-power fades *inside* the replaced region (the new take fades in over its first 5 ms and out over its last 5 ms, while the old take does the opposite). They shrink for takes shorter than 10 ms.
- **Crash safety.** A `.recording.json` marker is written when recording starts and refined with exact timing once audio arrives. If the app dies before the splice, the next open of that project splices the scratch file in. Splices write to a temp file and `rename(2)` over the take.
- **Stopping during a count-in** records nothing; an empty track stays empty.
- **Re-recording a track** deletes its Cleanup render (it no longer matches). If the Cleanup slider is above 0, the new take is re-rendered automatically.

## Cleanup

- **Engine: RNNoise** (BSD-3-Clause), vendored at **v0.1.1** because that version bundles its model weights in source. The newer release downloads its model from a server at build time. DeepFilterNet would need ONNX Runtime or a Core ML conversion plus a large model, and couldn't be built or verified in this environment. RNNoise is tiny, runs far faster than real time, and is also the natural candidate for a later live path. The BSD notice is shown in Settings → Acknowledgements, as the license requires.
- RNNoise works well on real-world (colored) noise: about −30 dB in tests. It barely touches synthetic white noise, which is expected from a model trained on recorded noise.
- **Blend model.** The offline pass renders one full-strength copy (denoise, then de-ess, then a tail suppressor for de-reverb), time-aligned with the original. RNNoise's one-frame delay is removed. The slider is a linear crossfade between the original and that render, using two player nodes per track, so slider moves are instant and non-destructive. Simplification vs. §5: de-ess and de-reverb are part of the render rather than "scaling in above 0.5"; they arrive proportionally with the blend. Revisit if it sounds wrong on guitar.
- About 5% of the original is kept under the denoised signal so the 100% position never sounds hollow.
- **De-reverb** is an in-house downward expander (`TailSuppressor`) that pulls down decaying room tails between phrases. It is not a true dereverberation model.
- **Cleanup defaults to 0 on every track.** The "Clean up this take?" banner appears only for takes recorded on the built-in speaker route. Accepting it sets the slider to 60%.

## UI

- **Tracks are revealed one at a time (owner request).** A new project shows one lane. A dashed **+** under the last lane reveals the next, up to four. Adding a lane arms it and rewinds to 0:00. The data model still holds four tracks; `Project.visibleTrackCount` controls how many lanes show, and a lane with audio is never hidden.
- **New Project (owner request).** A floating "New Project" pill sits at the bottom of the projects list, above the record bar. It opens a centered pop-up bubble (alert-style) with the name field focused and the default name ("New Project N") fully selected, so typing replaces it and Create keeps it. The project opens without recording. The big red button still creates a project and starts recording straight away.
- **Recently Deleted bin (owner request).** Deleting a project (swipe, or the project's menu) moves it to the bin with no confirmation. A "Recently Deleted" row appears at the bottom of the projects list when the bin isn't empty. Inside the bin, swipe right to recover and swipe left to delete permanently. Permanent deletion is the only action that asks for confirmation. Nothing expires automatically. Stored as `Project.deletedAt`.
- **Cleanup on/off button (owner request).** A thin "Clean up" pill under M/S in each lane turns Cleanup on (at the last level used, 60% the first time) or off. The Cleanup slider in the mixer still sets the amount.
- **A new track always starts at 0:00 (owner request).** Recording onto an empty track rewinds to the start first. Once a track has a take, overwrite-anywhere from the playhead applies as in the spec.

- **Waveform matches Voice Memos (owner request).** Rounded bars on a fixed time grid, redrawn every display frame from a playhead clock (`PlayheadClock`) anchored to the engine's host time, so scrolling is smooth rather than stepping at the model's 30 Hz tick. While recording, the "now" point is the right edge of every lane: new audio enters from the right and moves left, with no playhead line. During playback and when stopped, the playhead is a thin line at the center.
- **Lanes are iOS cards** (owner request): fixed-height rounded cards on the grouped background, separated by spacing, each with its own centered playhead. Dragging a waveform sideways scrubs every lane together; tapping a card arms it.
- **Press and hold to reorder lanes** (owner request), via `List.onMove`, disabled while recording. Track indices and their audio files never change. `Project.laneOrder` stores only the display order, which the mixer and export list also follow.
- **Mixing mode (owner request) replaces the side-by-side strips.** A segmented **Record | Mixing** switch sits under the nav bar. Mixing shows one track per page: swipe sideways, or tap the ‹ › arrows; the title and dots show where you are. The current track (compact card with M/S and a scrubbable waveform) and a one-line transport stay pinned at the top, so you can play and rewind while adjusting. Controls are native-style horizontal sliders in grouped sections: Clean Up (toggle + amount), Tone (High/Mid/Low), Character (Compressor, Space, Warmth when enabled), Level (Volume, meter in Developer Mode). Developer Mode adds a Master page and an "Advanced Controls…" row. This replaces the spec's "vertical sliders in mix strips"; every slider is now horizontal.
- **"Custom" macros.** Editing a section in Developer Mode stores an override. The macro then shows "Custom" (dimmed fill) while the override differs from its curve. Moving the macro slider again drops that section's override (the macro takes back control). "Reset to Macros" clears all of them.
- **Developer Mode off:** overrides, input gain and metronome settings are kept and overrides still apply (they're visible as "Custom"), but the master volume returns to unity and the metronome, meters, Warmth and export options switch off. The master volume has no visible indicator outside Developer Mode, so it shouldn't silently stay attenuated.
- **Metronome toggle** sits in the transport when Developer Mode is on; long-press it for tempo, count-in (none / 1 / 2 bars), beats per bar and click volume. The click grid is anchored to timeline 0, and the count-in plays the bars before the playhead. The click is never part of an export.
- **Single-track export** renders that track with its own processing and fader, ignoring mute and solo. **Mix export** respects mute and solo, so it matches playback.
- Exports are stereo. AAC 256 kbps 48 kHz by default; Developer Mode adds 24-bit WAV, 44.1 kHz and "Export All Tracks".

## Not verified here

This environment has no Xcode or iOS SDK. The core package is compiled and its tests run on Linux (Swift 5.10). The app target was only syntax-checked, so its first build in Xcode may need small fixes. Everything in §11 that needs a device is still to be checked: latency ≤ 5 ms, no dropouts while playing three tracks and recording a fourth, a phone call during recording, how Cleanup sounds on guitar, and echo cancellation quality.
