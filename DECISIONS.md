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
- **Three kits, eight pads each, each with its own pad colours:**
  - **Studio has two sounds, switched with a "Tight | Roomy" toggle under the kit picker (owner request).**
    - **Tight** (default for new drum tracks): *DRSKit* by the DrumGizmo team and Jes Eiler of DRSDrums, **CC BY 4.0** (commercial use allowed with credit; the credit, license link and list of changes are in Settings → Acknowledgements, and the license ships next to the samples). Built only from the close mics (kick in/out, snare top and bottom, hi-hat, ride and tom mics) with a little overhead for the cymbals, no ambience mics. Every mic is time- and polarity-aligned to the close mic before mixing (no flam or phasing), the kick takes the "beater stays on the head" articulation, and a short decay envelope damps the rings. Snare gets +4 dB above 3.5 kHz (the DRSKit snare is warm). Result vs Roomy: snare dies away 40 dB in about 130 ms instead of 330 ms, hats and high tom roughly half as long, cymbals about 1.3 s instead of 3.4 s. `DrumKit.studioTight`, folder `Drums/studio-tight`.
    - **Roomy**: the earlier kit, below. Its raw value stays `studio`, so existing tracks keep their sound.
    - Picking Studio from another kit starts on Tight; switching the sound re-renders the track like any kit change. A kit name this version doesn't know (from a newer build) falls back to Tight instead of failing the project.
  - **Studio · Roomy: real acoustic drums** from *Big Rusty Drums* (Karoryfer Samples, **CC0 1.0**: public domain, fine for a paid App Store app, no attribution required). Pads: kick, snare, closed hat, open hat, low tom, high tom, ride, crash. The close mics and overheads are pre-mixed into one mono sound per hit.
  - **Hand Percussion: real recordings** from the *Versilian Community Sample Library* (**CC0 1.0**): cajón bass and slap, bongo low and high, conga, shaker, tambourine, woodblock.
  - **808: synthesized** (an 808 is itself a synthesizer, so synthesis is the authentic sound).
  - Sampled pads carry **two recorded takes** that alternate on repeated hits (live and in the rendered track), so fast patterns don't sound machine-gunned. Samples are 48 kHz mono 16-bit CAF, trimmed to start within 1 ms of the hit and normalized; about 3.6 MB in total. Both licenses ship next to the samples and are credited in Settings → Acknowledgements. The samples ship as a plain `Drums` folder in the app (`FourTrack/Resources/Drums`), not as a Swift package resource bundle: a missing package bundle makes `Bundle.module` crash, which is what crashed build 25 when a drum track was created. If a sample is ever missing, that pad falls back to its synthesized sound. CI fails the upload if the folder isn't in the app.
  - Paid libraries were not used: their licenses allow use in your own music, not redistribution of the raw samples inside another app.
- **Drum layout (owner request).** Arming a drum track rearranges Record mode around playing:
  - **Lanes shrink to slim rows** (name, small waveform, armed dot). Tap a row to arm it (an audio lane brings the normal layout back), drag sideways to scrub, press and hold for Delete Track (with the usual confirmation). "+" stays available as a slim row.
  - **The pads fill the rest of the screen** (up to 150 pt tall). They fire on touch-down, play polyphonically through the drum track's chain, flash, and give a light haptic.
  - **Pad placement is the same in every kit,** like a finger-drumming controller: the groove sits on the bottom row under the thumbs (kick bottom-left, then snare, then hats or shaker/tambourine), with toms and cymbals or colour sounds on top, low on the left and high on the right. Pads are coloured by what they are, the same across kits: kick red, snare/clap orange, hats/shakers yellow, toms purple, cymbals teal, other accents blue. `DrumKit.padLayout` and `family(of:)` hold this; a test checks every pad appears once with kick and snare bottom-left.
  - **One-row transport:** time (and BPM when the click is on), return to start, play, a smaller record button in the middle, and a **metronome** toggle (press and hold for tempo and count-in). The metronome is shown for drum tracks even with Developer Mode off, because a click is essential for drums; it still never ends up in an export.
- **Drum takes start at the playhead (owner request),** even on an empty drum track; the rendered track is silent before the first hit. (Audio tracks still start an empty track at 0:00.)
- **Recording drums records hits, not the microphone.** Each hit is stored with its timeline time, shifted earlier by the output latency so it lands where the player heard it. On stop, hits in the recorded span replace the old ones (the same overwrite-anywhere rule as audio), and the whole track is rendered to its audio file. Mixing, export, mute/solo and waveforms then work exactly as for audio tracks.
- **Changing a kit re-renders every existing hit** with the new kit.
- **Play along without recording (owner request).** The pads always sound, whether the song is stopped or playing; tapping a drum track during playback brings up the pads without stopping the song. Hits are only recorded after pressing record. A caption over the pads says which is happening. An in-app test plays the song, switches to the drum track and checks the pads are heard and nothing is recorded.
- **Drum screen track row (owner request):** the armed drum track's name with **M**, **S** and **Q** above the kit picker.
- **Quantize (owner request), non-destructive.** Drum tracks already store hits (like MIDI), so quantize snaps them only when they are rendered and played; the hits keep their played timing. **Q** tap: on (1/16 by default) or off; press and hold Q to pick 1/4, 1/8, 1/16, 1/32, 1/8T or 1/16T. The grid is built from the tempo and beat unit at the moment quantize is turned on (stored with the track), so a later tempo change doesn't drag the drums away from the audio tracks; turn Q off and on to re-grid at a new tempo. Two hits of the same pad landing on one grid line merge into the louder one. New hits recorded while Q is on are snapped too.
- **Swing grids and Strength (owner: 1/8T felt off on the Pink Panther groove).** A triplet grid has three slots per beat, but a swing groove only plays the first and last, so hits near the middle got pulled onto a spot the groove never uses. Press and hold Q now also offers **1/8 Swing** and **1/16 Swing**: two slots per beat (or per eighth), the second on the last third (triplet / shuffle swing, 2:1). **Strength** (100% exact, 75%, 50%) moves hits only part of the way to the grid so the played feel survives. Older projects open at 100%.
- **Per-pad sound settings (owner request).** Press and hold any pad (0.55 s, not while recording) to open its settings bubble: **Volume** (same curve and unity detent as the track fader), **Tune** (±12 semitones, sampler-style so pitch and length move together), **Decay** (Natural down to a tight 25 ms damping, attack untouched) and **Tone** (darker/brighter shelf at 3 kHz). Each slider plays the pad when released, and there's a Play button.
  - The bubble's background is the pad's own colour (the same tint the pad uses), and its sliders and buttons take that colour too.
  - **Hold to Compare (owner request, replaces the Original | Yours switch, which wasn't intuitive):** one wide button under the pad's name. Press and hold it: the pad plays the kit's original sound at once, the button fills with the pad colour and reads "Original", and the sliders fade back to show they aren't what you're hearing. The pads on screen play the original while it's held. Let go: the pad plays your version again. It only appears once the sound has been changed.
  - **Apply (big, bottom) / Revert (small, top) (owner request).** Slider moves are heard on the pads straight away but only saved by **Apply**, which also re-renders the track's hits and closes the bubble (it reads "Done" when nothing changed). Swiping the bubble away discards the draft. **Revert** at the top: the first tap turns it into "Are you sure?" (red); a second tap goes back to the kit's own sound and saves that. Tapping anywhere else, moving a slider or Play cancels it.
  - Settings are stored per drum track and pad (`Track.padSettings`) as slider values. The live pads and the rendered track use the same processing (`PadProcessor`), so what you hear while playing is what gets recorded. Pads with adjustments show a small slider icon. Changes re-render the track's existing hits about half a second after the last move.

## Compressor (owner request)

- **In-house compressor replaces Apple's DynamicsProcessor.** The owner found 30% did nothing. It's a feed-forward design from Giannoulis, Massberg & Reiss (JAES 2012): soft knee, real ratio, smooth attack/release on the gain reduction, stereo-linked. Our own code, so there's no license to worry about. It runs as an in-process Audio Unit (`CompressorAU`), so the same code processes playback and export. If the unit ever fails to register, the chain falls back to DynamicsProcessor.
- **Retuned curve (replaces the spec's table):**

  | Slider | Threshold | Ratio | Knee | Attack | Release | Makeup |
  |---|---|---|---|---|---|---|
  | 0 | 0 dB | 1:1 (off) | 6 dB | 10 ms | 150 ms | 0 dB |
  | 0.3 | -20 dB | 2.5:1 | 8 dB | 10 ms | 120 ms | +4 dB |
  | 0.6 | -26 dB | 4:1 | 6 dB | 6 ms | 100 ms | +7 dB |
  | 1.0 | -34 dB | 8:1 | 4 dB | 2 ms | 70 ms | +11 dB |

  At the default, a -10 dBFS tone gets about 5 dB of gain reduction: clearly audible, still natural on voice and guitar. Makeup never exceeds the threshold depth, so a steady 0 dBFS input can't leave the compressor above full scale (tested at every slider position). Fast transients can overshoot by the makeup amount for a few milliseconds; the master limiter catches those.
- **Default is 0 (owner request).** New tracks start uncompressed, so what you hear is what you recorded; existing tracks keep their value. The spec's 0.3 default was dropped.
- Developer Mode's compressor section now shows Threshold, Ratio, Knee, Attack, Release and Makeup (Headroom is gone). Saved overrides from older builds load with a 4:1 ratio.

## Simple and Full mode (owner request)

- **Simple is the default (owner request).** The New Project bubble has a **Simple | Full** switch (Simple selected); the big record button makes a Simple project. Projects saved before modes existed open as Full. Projects in Simple mode show a small "Simple" tag in the list.
- **Simple mode:** record, play, scrub, name/reorder/delete audio tracks, a volume bar per track, Clean Up, undo/redo and export. No drum tracks (see "Simple mode: audio only" below). Hidden: the Record/Mixing switch and mixer, M/S, the metronome (and its project settings) and quantize.
- **⋯ → Simple Mode is a toggle, both ways, any time.** Turning it off goes straight to Full. Turning it on when the project uses something Simple hides first asks, then resets those settings (tone and effects to defaults, mute/solo off, metronome off; volume and Clean Up stay) as one undo step, so no hidden setting keeps changing the sound. Older projects open in Full mode.

## Top bar (owner request)

- The top bar holds only undo/redo (left), the project name and the ⋯ menu (right). **Share / Export** is the first item in the ⋯ menu, to keep the bar uncluttered.

## Undo / redo (owner request)

- **Undo and redo buttons at the top left of every project screen** (record, drums and mixing). The history is 1,000 steps per project and covers every edit: mixer and Developer Mode sliders, mute/solo, names, track type and order, adding and deleting tracks (including permanent deletes in the project's bin), recordings (audio and drums), kits, pad sounds, quantize and metronome settings. Playhead moves, arming and switching screens are not steps.
- **How audio comes back.** Each step stores the project as it was. Steps that rewrite audio also keep the affected files (takes, Cleanup renders, waveform caches, binned takes) as clones in the project's `.undo` folder; on iOS a clone costs no space until the original is overwritten, so only audio that really changed uses storage. Moves of the same slider within a second merge into one step.
- Undo and redo wait while recording, saving or a Cleanup render is running. The history lasts while the project is open and is deleted when it closes (or on next open after a crash). Undo never brings a project back out of Recently Deleted.
- Not covered: the projects list (deleting projects already goes through the bin), and app-wide Settings like Developer Mode.

## Haptics

- **Every press-and-hold gives a light buzz (owner request):** lifting a track to drag it, holding a drum pad, the slim drum-screen lanes, holding a tempo arrow (when repeats start), the time signature and Q hold menus, and renaming a project from the list.

## Sliders

- **Sliders only move for drags along their axis (owner request).** A vertical swipe that starts on a horizontal slider scrolls the page and leaves the value alone. Implemented with a UIKit pan recognizer that only begins when movement follows the slider's axis, and makes the enclosing scroll views (the mixer page and the track pager) wait for it to fail.

## Look (owner request)

- **Current iOS design (iOS 26 Liquid Glass).** The app builds with the iOS 26 SDK, so navigation bars, toolbars, menus, segmented controls and sheets use Liquid Glass automatically. On top of that, floating controls are glass: the transport is a floating glass panel, the "New Project" pill and the Cleanup banner use glass buttons, and the New Project bubble is a glass card with capsule buttons, like iOS 26 alerts. Content cards use larger continuous corners (22 pt). iOS 17–25 get a translucent material instead. Values live in `Theme.swift`.
- **The projects page is plain white,** like Voice Memos: list, bottom record area and background all use the system background, with no gray band or divider.

## Mixing page

- **Mixing shows only Solo (owner request).** The M button is gone from the pinned track card; Mute stays in Record view.

## Recording and timing

- **Alignment uses host time, not buffer counting.** Players start at a shared host time `T`. The recorder notes the host time of the first captured sample, and the splice skips `(T − firstSample + latency) × 48 kHz` frames of the scratch file. This removes tap-start jitter and pre-roll, and makes count-in work for free (the count-in audio is skipped).
- **Latency default** is the spec formula: `inputNode.presentationLatency + outputNode.presentationLatency + 2 × ioBufferDuration`. A calibrated value replaces it per route; the manual Developer Mode offset is added on top. **This still has to be verified on device** (acceptance: ≤ 5 ms on wired headphones). If takes land consistently early or late, either the formula double-counts or the tap timestamp is already compensated; run Calibrate and compare with the estimate shown in Settings.
- **Crossfades** are 5 ms equal-power fades *inside* the replaced region (the new take fades in over its first 5 ms and out over its last 5 ms, while the old take does the opposite). They shrink for takes shorter than 10 ms.
- **Crash safety.** A `.recording.json` marker is written when recording starts and refined with exact timing once audio arrives. If the app dies before the splice, the next open of that project splices the scratch file in. Splices write to a temp file and `rename(2)` over the take.
- **Stopping during a count-in** records nothing; an empty track stays empty.
- **Re-recording a track** deletes its Cleanup render (it no longer matches). If the Cleanup slider is above 0, the new take is re-rendered automatically.

## Cleanup

- **Engine (updated, owner found RNNoise too weak on vocals): Apple's Voice Isolation first, RNNoise as fallback.** Cleanup now runs the take offline through Apple's `AUSoundIsolation` Audio Unit. It's the on-device ML model behind FaceTime's "Voice Isolation" mic mode: built into iOS 16+, free to use in App Store apps, nothing to bundle, and far stronger on noise, room and backing-track bleed. It is set to 95% wet (a trace of the original stays under it), its reported latency is removed so the render lines up with the take, and our de-esser and tail suppressor run after it. If the unit is missing, rejects the format or returns silence, Cleanup falls back to RNNoise automatically. It is speech-trained: on guitar it will remove a lot, which is why Cleanup stays off by default. DeepFilterNet (MIT/Apache) remains a future option if an open-source model is ever preferred.
- **Speed (owner found Clean Up too slow):** the Voice Isolation model is the slow part, so a take is split into up to four segments (one per spare CPU core, each at least 8 s) rendered in parallel, each with its own engine and unit. Each segment starts 1 s early (discarded) so the model has settled by the join, and runs 20 ms past its end for a crossfade into the next, so joins are inaudible. The job also runs at user-initiated priority instead of utility, so iOS doesn't park it on the efficiency cores.
- **Original engine: RNNoise** (BSD-3-Clause), vendored at **v0.1.1** because that version bundles its model weights in source. The newer release downloads its model from a server at build time. DeepFilterNet would need ONNX Runtime or a Core ML conversion plus a large model, and couldn't be built or verified in this environment. RNNoise is tiny, runs far faster than real time, and is also the natural candidate for a later live path. The BSD notice is shown in Settings → Acknowledgements, as the license requires.
- RNNoise works well on real-world (colored) noise: about −30 dB in tests. It barely touches synthetic white noise, which is expected from a model trained on recorded noise.
- **Blend model.** The offline pass renders one full-strength copy (denoise, then de-ess, then a tail suppressor for de-reverb), time-aligned with the original. RNNoise's one-frame delay is removed. The slider is a linear crossfade between the original and that render, using two player nodes per track, so slider moves are instant and non-destructive. Simplification vs. §5: de-ess and de-reverb are part of the render rather than "scaling in above 0.5"; they arrive proportionally with the blend. Revisit if it sounds wrong on guitar.
- About 5% of the original is kept under the denoised signal so the 100% position never sounds hollow.
- **De-reverb** is an in-house downward expander (`TailSuppressor`) that pulls down decaying room tails between phrases. It is not a true dereverberation model.
- **Cleanup defaults to 0 on every track.** There is no "Clean up this take?" prompt after recording (owner request: it appeared after every speaker-route take); the Clean Up pill on each track does the job. A track with Clean Up on re-renders new takes automatically.

## UI

- **Tracks are revealed one at a time (owner request).** A new project shows one lane. A dashed **+** under the last lane reveals the next, up to four. Adding a lane arms it and rewinds to 0:00. The data model still holds four tracks; `Project.visibleTrackCount` controls how many lanes show, and a lane with audio is never hidden.
- **New Project (owner request).** A floating "New Project" pill sits at the bottom of the projects list, above the record bar. It opens a centered pop-up bubble (alert-style) with the name field focused and the default name ("New Project N") fully selected, so typing replaces it and Create keeps it. The project opens without recording. The big red button still creates a project and starts recording straight away.
- **Recently Deleted bin (owner request).** Deleting a project (swipe, or the project's menu) moves it to the bin with no confirmation. The bin is a trash icon next to Settings at the top of the projects list. Each binned project has two buttons, **Recover** and **Delete**; Delete is the only action that asks for confirmation. Nothing expires automatically. Stored as `Project.deletedAt`.
- **Deleting tracks (owner request).** Press and hold a track card: it lifts, and a bin rises at the bottom of the screen. Drag up or down to reorder, or onto the bin to delete. Dropping on the bin always asks "Are you sure you want to delete this track?". A deleted track goes to the project's own **Recently Deleted** (⋯ menu → Recently Deleted), keeping its audio, Cleanup render, drum hits and all settings, with the same Recover / Delete buttons. The lane disappears; the last remaining lane stays, empty. Recover puts the track into an empty lane, or reveals a new one; if all four lanes hold audio it asks you to delete one first. Audio waits on disk as `deleted-<id>.caf` in the project folder. The custom press-and-hold drag replaces the earlier `List.onMove` reordering (whose system drag lifted the whole row with its background and couldn't be dropped on a bin). Only the card lifts; it tracks the finger 1:1, the other cards spring out of its way with a selection tick per slot, it shrinks over the bin, and it settles into place with one spring on release.
- **Cleanup on/off button (owner request).** A thin "Clean up" pill under M/S in each lane turns Cleanup on (at the last level used, 60% the first time) or off. The Cleanup slider in the mixer still sets the amount.
- **A new track starts at 0:00 when recording from a stop (owner request).** Recording onto an empty track from a stop rewinds to the start first. Once a track has a take, overwrite-anywhere from the playhead applies as in the spec.
- **Punch-in while playing (owner request).** Pressing record while the song plays records the armed track from the live spot, without stopping or restarting anything: the other tracks and the click keep going, the armed track goes quiet, and the take starts where you pressed (placed exactly using the input's timestamps and latency compensation, as for any take). There's no count-in for a punch-in. Works for audio and drum tracks. The one exception is the very first recording in a session: turning the microphone on briefly stops the audio engine, so the song stops and recording starts right there (still no rewind, no count-in); after that, punch-ins are seamless.
- **Adding a track while the song plays (owner request)** shows and arms the new lane without stopping or rewinding; from a stop it still rewinds to 0:00.

- **Waveform matches Voice Memos (owner request).** Rounded bars on a fixed time grid, redrawn every display frame from a playhead clock (`PlayheadClock`) anchored to the engine's host time, so scrolling is smooth rather than stepping at the model's 30 Hz tick. While recording, the "now" point is the right edge of every lane: new audio enters from the right and moves left, with no playhead line. During playback and when stopped, the playhead is a thin line at the center.
- **Lanes are iOS cards** (owner request): fixed-height rounded cards on the grouped background, separated by spacing, each with its own centered playhead. Dragging a waveform sideways scrubs every lane together; tapping a card arms it.
- **Press and hold to reorder lanes** (owner request), via `List.onMove`, disabled while recording. Track indices and their audio files never change. `Project.laneOrder` stores only the display order, which the mixer and export list also follow.
- **Mixing mode (owner request) replaces the side-by-side strips.** A segmented **Record | Mixing** switch sits under the nav bar. Mixing shows one track per page: swipe sideways, or tap the ‹ › arrows; the title and dots show where you are. The current track (compact card with M/S and a scrubbable waveform) and a one-line transport stay pinned at the top, so you can play and rewind while adjusting. Controls are native-style horizontal sliders in grouped sections: Clean Up (toggle + amount), Tone (High/Mid/Low), Character (Compressor, Space, Warmth when enabled), Level (Volume, meter in Developer Mode). Developer Mode adds a Master page and an "Advanced Controls…" row. This replaces the spec's "vertical sliders in mix strips"; every slider is now horizontal.
- **"Custom" macros.** Editing a section in Developer Mode stores an override. The macro then shows "Custom" (dimmed fill) while the override differs from its curve. Moving the macro slider again drops that section's override (the macro takes back control). "Reset to Macros" clears all of them.
- **Developer Mode off:** overrides, input gain and metronome settings are kept and overrides still apply (they're visible as "Custom"), but the master volume returns to unity and the metronome, meters, Warmth and export options switch off. The master volume has no visible indicator outside Developer Mode, so it shouldn't silently stay attenuated.
- **Metronome for everyone (owner request), one row in the transport** (and on top of the drum transport):
  - **Mode button:** tap cycles **Click** (audible) → **Silent** (no sound, the beat lights still pulse; bigger lights) → **Off**. Silent mode runs the same click track at zero volume, so count-in and timing are identical.
  - **Time signature:** tap cycles 4/4 → 3/4 → 2/4; press and hold for 5/4, 6/4, 6/8, 7/8, 9/8, 12/8. In x/8 meters the BPM counts eighth notes.
  - **Changes never restart the click (owner request).** Tempo, time signature, volume and Click/Silent apply while it keeps playing: the click carries on from the beat it's on and just speeds up or slows down, within about 0.4 s (it's rendered in 0.2 s chunks). The beat lights follow the moved grid. Only turning the metronome on or off mid-song restarts it, to line it up with the tracks; the next play starts again on the timeline-0 grid.
  - **Tempo:** starts at **120 BPM** (the usual DAW default). ‹ › change it by the project's step (10 BPM by default); press and hold an arrow for 1 BPM steps that speed up the longer you hold. While playing, the click restarts once the tempo settles rather than on every step.
  - **Always starts Off (owner request).** Opening a project turns the metronome off; tempo, time signature, tempo step, count-in and volume are kept.
  - **First click was silent (fixed).** Turning the click on is often what first starts the audio engine; the first hardware render can come later than the 50 ms start lead, and a player whose start time has already passed silently skips everything queued after it. The engine now waits (up to 0.6 s, only on a fresh start) until the output has rendered before anything is scheduled.
  - **No separate play button (owner request; it replaced the earlier click-preview button).** Turning the metronome on (Click or Silent) starts it keeping time at once: on its own if the song isn't playing, or joining the song on the right beat if it is. It runs on the song's beat grid from the playhead, so when you press play or record it carries straight on, and after you pause or stop (once a take has saved) it keeps going from where the song stopped. Moving the playhead re-aligns it. Off stops it. Silent runs the same click at zero volume so the lights keep time.
  - **Beat lights:** one dot per beat, the current one pulses (downbeat in red), including during a count-in.
  - **No headphones pop-up (owner request; it was removed after first shipping as a once-per-install tip).** Recording with the click on the speaker just records; echo cancellation keeps the click out of the take.
  - **Project Settings → Metronome (This Project):** tempo-arrow step (1–40 BPM), count-in (none / 1 / 2 bars, default 1) and click volume. Old projects keep their tempo and on/off state.
  - The click grid is anchored to timeline 0, the count-in plays the bars before the playhead, and the click is never part of an export.
  - **Usable while recording (owner request).** The metronome row stays live during a take: switch the click on (it joins on the beat of what's playing, no count-in), off, Click/Silent, or change tempo and signature. Only the stand-alone click preview is disabled while the song plays or records.
  - **Beat lines behind the waveforms (owner request, may be removed):** whenever the metronome is Click or Silent, every lane (record, drum and mixing screens) draws a faint hairline per bar and a fainter, shorter one per beat, scrolling with the audio. Beat lines drop out below 9 pt spacing so fast tempos stay calm. Turning the metronome Off removes them; simple projects never show them. While playing they follow the click's live grid (so tempo changes bend them), and when stopped they show the timeline-0 grid the next play starts on.
- **Single-track export** renders that track with its own processing and fader, ignoring mute and solo. **Mix export** respects mute and solo, so it matches playback.
- Exports are stereo. AAC 256 kbps 48 kHz by default; Developer Mode adds 24-bit WAV, 44.1 kHz and "Export All Tracks".

## Drum pads balanced by loudness (owner: some drums far too loud by default)

- Every sample shipped peak-normalized (all peaks at 0.89), which made long and bright sounds far louder than kicks: in Studio Tight the crash measured ~6 dB over the kick, in the 808 kit the kick ~10 dB over the rim. Pads are now balanced by measured loudness (`DrumLevels`): ITU-R BS.1770 K-weighting (the LUFS curve) over each one-shot's loudest 150 ms, then a gain to a target for its role, relative to the kit's kick: snare -1 dB, clap -3, toms/congas/bongos -3, rim -6, crash -6, open hat -7, cowbell/woodblock -7, closed hat -8, ride -8, tambourine -8, shaker -9. Every kit's kick aims at the same loudness, so switching kits doesn't jump in level. Peaks stay at or under 0.9, so a quiet sample is only raised as far as its peak allows (and the rest of that kit follows it). Each recorded take is balanced on its own, so alternating takes match.
- Applied where samples are loaded, so the live pads and the recorded track match. Pad Volume in the hold bubble still adjusts from there. Existing drum takes re-render once (renderer version 2).

- **808 kick (owner: hard to hear).** It was a pure sine sliding to 44 Hz, almost all below what a phone speaker plays. It's now synthesized like the 808s used on records: a 160 → 48 Hz drop driven into soft saturation (tanh, drive 4) so its harmonics carry on small speakers, plus a 6 ms beater click; and the 808 kick sits 5 dB above the rest of its kit (`DrumLevels.kickEmphasis`). Above 150 Hz (roughly what a phone speaker reproduces) it now measures level with the 808 snare. Existing drum takes re-render once (renderer version 3).

## Drum voices choke like real drums (owner report: 808 kick distorting on repeats)

- Repeated hits used to stack: every hit rang out in full on its own voice, so a quick run of 808 kicks (long sine tails) piled up, phased against each other and drove the clipper. Now, live and in the recorded track alike (`DrumVoicing`), **hitting a drum again fades out its previous ring over 4 ms** (no click), finishing just before the new hit starts so the two never overlap (an 808 tail and a new attack in phase would otherwise peak far above either; live, the new note waits those 4 ms), the way a re-struck drum or a drum machine behaves, and **the closed and open hi-hat choke each other**. Different drums still overlap freely.
- The live pads are now a small sampler inside one `AVAudioSourceNode` (16 voices, the oldest-to-finish is reused when all are busy). A tap only queues a note for the audio thread; no player is started or stopped from the main thread, so taps can never block on the audio hardware (the cause of the build-25 freeze report).

## Deleting a track: press, hold and drag to the bin (owner request; the edge swipe was tried and dropped)

- Press and hold a card for 0.2 s (it lifts with a tap of haptics), then drag: up or down reorders, onto the bin that rises at the bottom deletes it after the "Are you sure you want to delete this track?" confirmation. The drum screen's slim rows keep press-and-hold → Delete.
- Made faster and tighter after the owner found the first version slow and laggy: the hold is 0.2 s instead of 0.3 s, and the held card's position lives in its own small observable object read only by that card (`LaneMotion` / `FollowsFinger`). Before, every finger movement redrew the whole project screen, every waveform included, so the card trailed the finger. Now per-frame work is one offset; the rest of the screen only updates when the card crosses into another slot or reaches the bin. On drop, the reorder happens without animation while the card stays exactly under the finger, then it springs into its slot.

## Recording through the speaker: echo cancellation on by default (owner request)

- Voice Memos can play a recording out loud while you record over it without capturing the playback. We now do the same: when a take is recorded through the **iPhone speaker**, Apple's voice processing (`AVAudioInputNode.setVoiceProcessingEnabled`, acoustic echo cancellation) removes the playing tracks and the click from the microphone. It replaces spec §4.5's "Developer Mode toggle only, if it sounds acceptable": the owner wants this as the normal behaviour.
- **Settings → Recording Without Headphones → Keep Playback Out of Recordings**, on by default, available in every project (Simple too).
- **Only when there is something to cancel (owner: piano takes came out pumping and distorted).** Voice processing is voice-call DSP; on instruments it rides the level and adds harsh peaks. It's now used only for a speaker-route take while something is audible (another unmuted track with audio, or the click), and it's switched off again as soon as that take stops, so playback and solo takes always use the plain microphone, like Voice Memos. Previously it switched on for every speaker take and then stayed on.
- Only used on the speaker route. With wired or Bluetooth headphones the mic hears nothing to cancel, so it's switched off and the mic's tone is untouched. Plugging headphones in while stopped turns it off again.
- Tuned for music rather than calls: automatic gain control off, other apps' audio ducked as little as possible.
- Switching it on or off restarts the engine, so it's only done while stopped. Once on, it stays on for speaker playback, so later punch-ins while playing stay seamless. If the first speaker punch-in needs it switched on, the take starts from that spot after a brief stop, just like the very first recording does.
- Latency: echo cancellation adds its own delay, so a speaker calibration measured without it doesn't apply. While it's on, takes are moved by the engine's estimate of the processed path, plus any manual offset. Latency calibration always runs with it off, since it would cancel the calibration clicks.
- **Needs checking on a device:** how much of the playback is removed at loud speaker volume, how the processed mic sounds on singing and guitar, and whether speaker overdubs line up.

## Simple mode: audio only (owner request)

- Simple projects have **only audio tracks**. Each track card shows its name, Clean Up and a **volume bar along the bottom** (same fader as the mixer: unity detent at 0 dB, double tap resets). Nothing else: no drums, mixer, mute/solo, metronome or quantize.
- "+" adds an audio track straight away (no Audio/Drum menu), and ⋯ has no "Make a Drum Track".
- **Switching to Simple** resets the hidden settings (tone, compressor, space, warmth, mute/solo, metronome, master volume) after a confirmation, keeps volume and Clean Up, and turns empty drum tracks into audio tracks. If a drum track has a take, the switch is refused with "Delete Drum Tracks First", rather than silently deleting a part.
- Drum tracks in the project's Recently Deleted can't be recovered while the project is Simple (the message points to Full mode).
- **Older Simple projects that already have drum takes open as Full** so nothing is lost; their empty drum tracks become audio tracks otherwise.

## Feel and intuitiveness pass

- **Tapping a track's name arms it** when it isn't armed (the same as tapping anywhere on its card); tapping the armed track's name renames it. Before, the name was the one spot on a card that renamed instead of arming, which is where people tap first.
- **A light tick when arming a different track,** on both the lane cards and the slim drum-screen rows.
- **Scrubbing ticks on every bar line** while the beat lines are showing, and at the start and end of the song, so you can feel your place without looking.
- **Renaming a track to the same name** no longer adds an undo step.
- Removed the leftover "Clean up this take?" banner code (the pop-up was already switched off).

## CI minutes (repo stays private)

- GitHub counts macOS minutes ten times against the plan's 2,000 free minutes. To stretch them: the core package tests run on Linux (1x); the app tests, archive and upload share one macOS job (one runner, one checkout, no separate build step); and pushes that only touch Markdown don't build at all. Pushes still ship to TestFlight automatically, so changes are batched into fewer pushes.

## Testing on the simulator

- CI runs app tests inside the real app on an iOS Simulator before every TestFlight upload: creating a drum track and playing every kit, drawing the drum screen, and rendering a track through the full chain (EQ → compressor → reverb) at several compressor settings. A UI test taps through New Project → + → Drum Track → pads exactly as a person would. Crash reports are printed in the CI log if anything fails.
- These tests caught the in-house compressor's render block rejecting its input (error -50, "cannot play"). It now pulls its input straight into the output buffers and processes in place.

## Not verified here

This environment has no Xcode or iOS SDK. The core package is compiled and its tests run on Linux (Swift 5.10). The app target was only syntax-checked, so its first build in Xcode may need small fixes. Everything in §11 that needs a device is still to be checked: latency ≤ 5 ms, no dropouts while playing three tracks and recording a fourth, a phone call during recording, how Cleanup sounds on guitar, and echo cancellation quality.

## Live pads ignore mute and solo (owner request)

- Mute and solo silence a track's recorded take (its players), not its whole channel, so live drum pads routed through the armed drum track's chain are always heard, even with another track soloed or the drum track muted. Faders keep their value either way, and a muted track's reverb tail now rings out naturally instead of cutting.

## Lock screen controls (owner request)

- The open project shows on the lock screen and in Control Center (title = project name; "Four-Track", or "Recording" during a take). Play, pause, skip back / forward 15 s and dragging the progress bar drive the transport while the phone is locked; the app already keeps playing in the background (audio background mode). Pause during a take stops recording, keeping the take. Skips and scrubbing are ignored while recording. The controls are registered when a project opens and removed when it closes.

## iPhone Duo (owner request, following Apple's "Prepare for iPhone Duo")

- Audit: the app uses none of the patterns Apple asks to remove (`UIScreen.main`, device orientation or idiom checks, hard-coded screen sizes, `UIWindow(frame:)`, fill-only media). Layout already comes from available space.
- **Resizable and rotatable:** removed `UIRequiresFullScreen` and allowed portrait and both landscapes, so the app can fill the inner display and resize when the device folds or unfolds instead of running letterboxed.
- **Wide layouts:** whenever the space is clearly wider than tall (landscape, the unfolded inner display), measured live with `onGeometryChange`:
  - the record screen puts the transport in a 360 pt column beside the track cards;
  - the drum screen puts the slim lanes, kit and transport in a 380 pt scrolling column on the left and the pads fill the rest.
  - The pad sound bubble scrolls when it's short.
- **SDK:** full iPhone Duo resizing needs apps built with the iOS 27 SDK. The GitHub macOS runners only have Xcode 26.x so far; CI now picks the newest Xcode 27 automatically when it appears (falling back to the newest 26, with a warning). Not tested on an iPhone Duo or its simulator (needs Xcode 27.1).

## Hide the drum pads (owner request)

- A grab handle sits in the middle of the drum screen's top row, between the track name and M / S / Q. Pull it down (or tap it) and the pads go away: every track shows as a full-size card, exactly as when an audio track is armed, with the normal transport. A "Drum Pads" pull tab above the transport brings them back (pull up or tap). Pressing record on a drum track brings the pads back too, since you need them to play. Hidden stays hidden while you switch between tracks during the session; it isn't saved with the project.
