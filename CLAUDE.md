# Four-Track: Build Spec

Native iOS multitrack recorder that feels like Apple Voice Memos, not a DAW. Four fixed tracks, one take per track, tape-style keep-or-overwrite. The constraint is the feature: a few controls that always sound good and cannot be misused. Depth lives behind a Developer Mode toggle.

Read this whole file before writing code. When a decision is not covered here, choose the simplest option that preserves the Voice Memos feel, and note the decision in `DECISIONS.md`.

---

## 1. Platform and stack

- iOS 17+ (raise to 18 only if a needed API requires it). iPhone first, iPad layout can come later.
- Swift 5.10+, SwiftUI for all UI, Swift Concurrency where it fits.
- Audio: `AVAudioEngine`, `AVAudioSession`, `AVAudioFile`. No third-party audio frameworks for the core.
- Persistence: SwiftData (or a simple Codable JSON store if SwiftData causes friction) for project metadata; audio as files on disk.
- No backend, no accounts, no analytics in v1.
- Target: App Store release under the existing Apple Developer account.

---

## 2. Product rules (non-negotiable)

1. **Projects list, Voice Memos style.** The home screen is a list of projects (like the list of memos). Each project is one four-track session.
2. **Four tracks per project, fixed.** Not configurable in v1.
3. **One take per track.** Recording onto a track replaces the audio from the playhead forward. There is no take history, no alternates, no version tree.
4. **Overwrite-anywhere.** Scrub the playhead to any point, press record, and the track is overwritten from that point for as long as recording continues. Audio after the point where recording stops is preserved. No punch-in region setup.
5. **Monitoring while recording.** All other unmuted tracks play while recording, so layering is natural (guitar first, vocal over it).
6. **Faders only, no knobs, anywhere.**
7. **Default view stays almost boringly simple.** Anything Logic-like goes behind Developer Mode.
8. **Exports:** mixed bounce, or a single track on its own. That is all in the default UI.

---

## 3. Screens and interaction

### 3.1 Projects list
- Mirrors Voice Memos: list of projects with name, date, duration.
- Big record button at the bottom creates a new project and immediately starts recording on Track 1.
- Swipe to delete (with confirmation), tap to open, long press to rename.

### 3.2 Project view (record mode, default)
- Four horizontal track rows stacked vertically. Each row: editable name (default "Track 1"... "Track 4"), compact waveform, mute (M), solo (S), and an arm selector (tap the row to arm it; armed row is highlighted).
- A shared playhead across all four tracks. Drag the waveform area to scrub, like Voice Memos.
- Transport at the bottom: large red record button (records onto the armed track from the playhead), play/pause, skip back 15s, skip forward 15s, return to start.
- Live waveform draws in real time on the armed track while recording.
- Auto-save always. No save dialogs.
- Top bar: project name, Mix toggle, share/export button, overflow menu (Developer Mode lives in Settings, not here).

### 3.3 Mix mode (toggle)
- Same screen flips into four vertical channel strips side by side.
- Per strip, top to bottom: track name, Cleanup, Warmth (post-v1, hidden flag), Space, Compressor, High, Mid, Low, Volume fader, M/S buttons.
- Transport stays available so the user can play while mixing.
- A small master strip is not needed in v1; master volume lives in Developer Mode.

### 3.4 Slider design
Build one reusable `CenteredSlider` SwiftUI component and one `MacroSlider`. These matter a lot; match the current Voice Memos slider look.

- **CenteredSlider** (EQ bands): value range -1...1, neutral at 0. Blue fill grows from the center toward the thumb (left or right). White circular thumb. Haptic tick (`UIImpactFeedbackGenerator(style: .light)`) when crossing 0, with a small magnetic detent at 0. Double tap resets to 0.
- **MacroSlider** (Compressor, Cleanup, Space, Warmth): value range 0...1, fill grows from the left. Same thumb and styling. Double tap resets to default.
- **Volume fader:** 0...1 mapped to dB (see section 5), default at unity (0 dB) with a detent there.
- Sliders are horizontal in record contexts and vertical in mix strips. Same component, `axis` parameter.
- All sliders are large enough to use with a thumb; minimum 44pt hit target.
- VoiceOver: each slider exposes a label and a spoken value ("Low, plus 3 decibels"; "Compressor, 40 percent").

### 3.5 Export sheet
- Two buttons: "Export Mix" and "Export Track..." (then pick the track).
- Output via the system share sheet.
- Default format: AAC .m4a 256 kbps. Developer Mode adds WAV and per-track batch export.

---

## 4. Audio architecture

### 4.1 Session
- `AVAudioSession` category `.playAndRecord`, mode `.default`, options `[.defaultToSpeaker, .allowBluetoothA2DP]`.
- Preferred sample rate 48 kHz, preferred IO buffer duration ~5 ms (request, then read back what the system gives).
- Request microphone permission on first record attempt, with a clear denied state that links to Settings.

### 4.2 Engine graph

```
inputNode ──tap──> Recorder (writes armed track)

For each track i in 1...4:
  AVAudioPlayerNode_i
    -> EQ_i (AVAudioUnitEQ, 3 bands)
    -> Compressor_i (AVAudioUnitEffect, Apple DynamicsProcessor)
    -> Saturation_i (AVAudioUnitDistortion, bypassed in v1 unless Warmth enabled)
    -> Reverb send / Reverb_i (AVAudioUnitReverb, wetDryMix driven by Space)
    -> trackMixer_i (AVAudioMixerNode: volume, mute, solo logic)
  -> mainMixer -> outputNode
```

- Keep the graph built once per project open. Do not rebuild nodes while playing.
- Solo logic: if any track is soloed, non-soloed tracks are silenced at their `trackMixer` volume, without losing their fader value.
- Working format everywhere: 48 kHz, Float32, non-interleaved. Mono tracks (phone mic is mono); pan is not exposed in v1, tracks are centered.

### 4.3 Recording and overwrite-anywhere
- Each track is one continuous audio file on disk (`track1.caf`... `track4.caf`), Float32 or 24-bit PCM, 48 kHz mono.
- On record start at playhead time `t0`:
  1. Start all non-armed tracks playing from `t0` (monitoring).
  2. Install a tap on `inputNode`, buffer incoming audio into a temp file.
- On stop at time `t1`: splice the temp recording into the track file, replacing samples in `[t0, t1)`. Samples after `t1` stay. If `t1` exceeds the current track length, the track grows; other tracks are treated as silence beyond their end.
- Apply a short crossfade (around 5 ms) at both splice edges to avoid clicks.
- The splice must be atomic: write a new file, then replace the old one. A crash mid-splice must never corrupt the existing take.
- Waveform data: compute and cache a downsampled peak array per track (e.g. one peak per ~10 ms) after each splice, for fast drawing.

### 4.4 Latency compensation (critical for layering)
- Recorded audio arrives late relative to what the user heard. Compute round-trip latency as `inputNode.presentationLatency + outputNode.presentationLatency + 2 * session.ioBufferDuration` (verify empirically) and shift the recorded audio earlier by that amount before splicing.
- Store the measured offset per audio route (built-in speaker, wired headphones, Bluetooth). Bluetooth latency is large and variable; show a one-time tip recommending wired headphones or the speaker path for overdubs.
- Developer Mode exposes a manual latency offset slider (ms) and a "calibrate" helper (play click, record it back, measure).

### 4.5 Bleed when recording without headphones
- When the output route is the built-in speaker, the mic will pick up the backing tracks.
- v1 approach, in order of preference:
  1. Run Cleanup (section 6) as a post-record pass on that take; offer it automatically with a non-blocking "Clean up this take?" banner.
  2. Optionally evaluate `inputNode.setVoiceProcessingEnabled(true)` (Apple echo cancellation) on the speaker route. It reduces bleed but alters tone and forces processing; test it, and only ship it behind a Developer Mode toggle if it sounds acceptable.
- Never block recording on this. Headphones are the clean path.

### 4.6 Interruptions and route changes
- Handle `AVAudioSession.interruptionNotification` (calls, Siri, alarms): stop recording, finalize the splice with what was captured, pause transport. Never lose the take.
- Handle `routeChangeNotification` (headphones unplugged): pause playback, keep the engine valid, switch the latency offset for the new route.
- Handle engine configuration changes (`AVAudioEngineConfigurationChange`): rebuild connections safely and restore state.
- App backgrounded during recording: keep recording (enable the audio background mode) and finalize on stop.

---

## 5. Macro sliders: parameter mappings

Each macro is one slider driving several real parameters along a curve designed so every position sounds acceptable. Put all mappings in one file (`MacroCurves.swift`) as pure functions so they are easy to tune and unit test. Values below are starting points; tune by ear.

### Volume
- Slider 0...1 to dB: 0 = -inf (mute), 0.75 = 0 dB (unity, detent), 1.0 = +6 dB. Use a smooth audio taper between points.

### 3-band EQ (AVAudioUnitEQ, 3 bands)
- Low: low shelf at 120 Hz. Mid: parametric at 1.2 kHz, bandwidth ~1.5 octaves. High: high shelf at 8 kHz.
- Slider -1...1 maps to -12...+12 dB gain, linear. Detent at 0 = 0 dB.

### Compressor (Apple DynamicsProcessor)
Slider 0...1, default 0.3. Interpolate:

| Slider | Threshold (dB) | Headroom (dB) | Attack (s) | Release (s) | Makeup gain (dB) |
|---|---|---|---|---|---|
| 0.0 | 0 (effectively off) | 20 | 0.010 | 0.15 | 0 |
| 0.5 | -18 | 8 | 0.008 | 0.12 | +4 |
| 1.0 | -30 | 3 | 0.003 | 0.08 | +8 |

Makeup gain keeps perceived loudness roughly steady as compression increases. Clamp so the output never clips at max settings (verify with a loud test file).

### Space (AVAudioUnitReverb)
- Preset `.mediumRoom` (try `.plate` for vocals).
- Slider 0...1 maps to wetDryMix 0...35 (never fully wet in the simple UI). Use a gentle curve (slider squared) so the first half is subtle.

### Warmth (post-v1, behind a feature flag)
- `AVAudioUnitDistortion` with a soft-clip style preset, or a small custom waveshaper `AUAudioUnit` if presets sound harsh.
- Slider 0...1 maps to wetDryMix 0...25 plus pre-gain 0...+6 dB, with output trim to compensate.

### Cleanup
- See section 6. Slider 0...1 maps to denoise strength; de-reverb and de-ess scale in with it above 0.5.

---

## 6. Cleanup (the differentiator)

Goal: make phone-mic takes sound clean (noise, room, harsh "s", speaker bleed) with one slider.

- **v1: offline "polish" pass.** Runs on a track after recording, writes a processed copy, and the slider value controls the blend between original and processed. Original audio is kept until the user records over the track, so changing the slider is non-destructive.
- **Engine candidates (evaluate, pick one, record the choice in `DECISIONS.md`):**
  - DeepFilterNet (MIT/Apache-2.0): high quality speech enhancement; convert to Core ML or run via ONNX Runtime. Best quality candidate.
  - RNNoise (BSD-3-Clause): tiny, fast C library; good noise reduction, weaker on reverb. Best fallback and candidate for a future live path.
- Verify every model and library license is App Store compatible (no GPL code linked into the app).
- De-esser: a simple high-band dynamic attenuation stage applied above slider 0.5, implemented with a band-split plus a gain reducer. Keep it in-house, no extra dependency.
- Processing runs on a background task with a progress indicator on the track row. The UI stays usable.
- Note for music: speech-trained denoisers can damage guitar. Default Cleanup to off for tracks, and make the auto-offer banner only appear when the speaker route was used. Test thoroughly on acoustic guitar and voice.
- **Later:** live cleanup during recording, only if CPU and battery budgets allow on the minimum supported device.

---

## 7. Developer Mode

Toggle in Settings, off by default. When on, it reveals:

- Exploded controls per macro: compressor (threshold, headroom, attack, release, makeup), EQ as parametric (frequency, gain, bandwidth per band), reverb (preset picker, wet mix).
- Level meters per track and on the master, with clip indicators. Master volume fader.
- Input gain per track (pre-record trim; implement as digital gain on the recorded signal, since iOS input gain control is limited).
- Metronome / click track with BPM, plus a 1 or 2 bar count-in. These are the most useful items here; make them a single visible toggle in the transport when Developer Mode is on.
- Latency offset slider and calibration helper.
- Export options: WAV or AAC, 44.1 or 48 kHz, export all four tracks at once.
- Voice processing (echo cancellation) toggle for speaker-route overdubs, if it passes testing.

Switching Developer Mode off hides the controls but keeps the values. The simple macro slider should reflect a "custom" state if exploded values no longer match its curve.

---

## 8. Data model

```swift
Project {
  id: UUID
  name: String
  createdAt: Date
  updatedAt: Date
  durationSeconds: Double        // longest track
  playheadSeconds: Double        // restored on open
  tracks: [Track]                // always exactly 4
}

Track {
  index: Int                     // 0...3
  name: String
  audioFileName: String?         // nil = empty track
  cleanedFileName: String?
  mute: Bool
  solo: Bool
  volume: Double                 // 0...1 slider value
  eqLow, eqMid, eqHigh: Double   // -1...1
  compressor: Double             // 0...1
  space: Double                  // 0...1
  warmth: Double                 // 0...1
  cleanup: Double                // 0...1
  devOverrides: DevParams?       // exploded values when edited in Developer Mode
}
```

- Store slider values, not raw DSP parameters, so curve tuning in future versions improves old projects.
- Files live in `Application Support/Projects/<project-id>/`.

---

## 9. Suggested code structure

```
FourTrack/
  App/            FourTrackApp.swift, AppSettings.swift
  Models/         Project.swift, Track.swift, DevParams.swift
  Audio/          AudioSessionManager.swift, MixerEngine.swift,
                  TrackChain.swift, Recorder.swift, Splicer.swift,
                  LatencyCalibrator.swift, Metronome.swift,
                  Exporter.swift, MacroCurves.swift
  Cleanup/        CleanupProcessor.swift (protocol), DeepFilterProcessor.swift
                  or RNNoiseProcessor.swift, DeEsser.swift
  Waveform/       PeakGenerator.swift, WaveformView.swift
  UI/             ProjectsListView.swift, ProjectView.swift, TrackRowView.swift,
                  MixView.swift, ChannelStripView.swift, TransportView.swift,
                  CenteredSlider.swift, MacroSlider.swift, VolumeFader.swift,
                  ExportSheet.swift, SettingsView.swift
  Tests/          MacroCurvesTests.swift, SplicerTests.swift, ProjectStoreTests.swift
```

Keep audio code free of SwiftUI imports. UI talks to an `@Observable` project view model, which talks to `MixerEngine`.

---

## 10. Build order (each step must work end to end before the next)

1. Audio session, permission flow, a single track that records and plays back.
2. Four-track graph with mute, solo, volume; play all tracks in sync.
3. Overwrite-anywhere splice with crossfades and atomic file replacement; unit tests for the splicer.
4. Latency compensation and route handling; verify layered takes line up on device with wired headphones.
5. Projects list, project view, waveforms, scrubbing, track naming, auto-save.
6. `CenteredSlider`, `MacroSlider`, `VolumeFader` components.
7. Mix mode: EQ and compressor macros wired to the graph.
8. Space macro.
9. Export: mix bounce (offline render with `enableManualRenderingMode`) and single track.
10. Cleanup offline pass with the chosen engine, blend slider, progress UI.
11. Interruptions, engine config changes, background recording hardening.
12. Developer Mode: exploded controls, meters, metronome and count-in, latency calibration, export options.
13. Warmth macro behind its flag.
14. Accessibility pass, dark mode check, App Store assets.

---

## 11. Acceptance criteria for v1

- A new user can record a guitar part, then a vocal over it, and export the mix without reading any instructions.
- Overdubs recorded on wired headphones line up within 5 ms of the backing track.
- Recording over the middle of a track preserves audio before and after the replaced section with no audible clicks.
- A phone call during recording keeps everything captured up to the interruption.
- Every macro slider position, from minimum to maximum, produces no clipping and no obviously broken sound on the test files (spoken voice, sung voice, acoustic guitar, loud strummed guitar).
- Exported mix sounds the same as playback in the app.
- Works on the minimum supported device without dropouts while playing three tracks and recording a fourth.

---

## 12. Non-goals for v1

- Multiple takes, comping, or take history.
- More than four tracks.
- Timeline or region editing (cut, move, trim) beyond overwrite-anywhere.
- Panning, sends, buses, plugins (AUv3 hosting), MIDI.
- Cloud sync, collaboration, accounts.
- Knobs.

---

## 13. Open decisions (ask the owner before locking)

- Live cleanup at launch, or post-record polish only? (Default: post-record only.)
- Minimum supported iPhone model and iOS version.
- Whether Warmth ships in v1 or the first update. (Default: first update.)
- App name and icon.

---

## 14. Maintenance rules (owner)

- **Privacy policy:** whenever a change affects what data the app touches, stores, shares or sends (new permissions, network use, sync, analytics, imports/exports), update `FourTrack/UI/PrivacyPolicyView.swift` (text and `lastUpdated`), run `python3 scripts/privacy_html.py` to refresh the hosted copy in `docs/privacy.html`, and update `PrivacyInfo.xcprivacy` and the App Privacy answers in `docs/app-store.md` if they change.
