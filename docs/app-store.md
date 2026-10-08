# App Store listing

Paste these into App Store Connect → your app → the version page (and App Information / App Privacy / Age Rating). Character limits are noted; everything below fits.

## App Information

| Field | Value |
|---|---|
| Name (30) | Four-Track (if taken: **Four-Track Recorder**) |
| Subtitle (30) | Layer songs like Voice Memos |
| Primary category | Music |
| Secondary category | (none) |
| Privacy Policy URL | https://thomasragosta1.github.io/mixer/privacy.html |
| Support URL | https://thomasragosta1.github.io/mixer/ |
| Marketing URL | (leave empty) |
| Copyright | 2026 Thomas Ragosta |

## Promotional text (170, can change any time without review)

Record a guitar part, sing over it, add drums with your fingers, and send the mix to a friend. Four tracks, a few faders, nothing to learn.

## Description (4000)

Four-Track is a multitrack recorder that feels like Voice Memos. Press record, play your part, then layer the next one over it. That's the whole idea.

RECORD IN LAYERS
• Four tracks per song. Record a guitar part, then sing over it while it plays back.
• Scrub to any point and record over just that section. Everything before and after stays put.
• Hear every other track while you record, so new parts land in time.
• Live waveforms, a shared playhead, and auto-save. No save dialogs, ever.

SOUNDS GOOD WITHOUT TRYING
• Clean Up takes room noise and harshness out of phone-mic takes with one switch.
• Speaker playback is kept out of your recording when you're not wearing headphones.
• Every control is a slider tuned so any position sounds right. No knobs, no menus of plug-ins.

SIMPLE OR FULL
• Simple mode: tracks, a volume bar on each, Clean Up, export. Done.
• Full mode adds a mixer with EQ, compression and reverb per track, mute and solo, a metronome with count-in, and pinch-to-zoom waveforms.

DRUMS UNDER YOUR FINGERS
• Turn a track into drum pads: studio kit, 808 or hand percussion.
• Play them live over your song, then tidy the timing with quantize and swing.
• Hold a pad to tweak its sound.

BRING IN VOICE MEMOS
• Share a recording from Voice Memos or Files straight to Four-Track and start a new song from it, or add it as a track to one you're working on.

SHARE THE RESULT
• Export the full mix or a single track as a high-quality AAC file and send it anywhere.
• Play and pause from the lock screen.

PRIVATE BY DESIGN
• Your songs stay on your iPhone. No account, no ads, no tracking, no data collected.

## Keywords (100, comma-separated, no spaces after commas)

multitrack,recorder,overdub,songwriting,demo,4 track,guitar,vocal,drum pads,metronome,voice memo

## What's New (first release)

First release.

## Screenshots

- Required: **6.9-inch iPhone** (1320 × 2868 or 1290 × 2796). App Store Connect scales these down for smaller iPhones, so one set is enough. iPad isn't needed (the app is iPhone-only).
- Captured automatically: Actions → **Screenshots** → Run workflow. It runs the app on a 6.9-inch simulator with demo projects (synthesized audio, not your real projects) and commits the images to `docs/screenshots/`:
  1. `01-projects.png` – the projects list
  2. `02-tracks.png` – a song with three tracks and the metronome
  3. `03-mixing.png` – the mixer
  4. `04-drums.png` – drum pads
  5. `05-simple.png` – a Simple mode song
  6. `06-export.png` – export
- Suggested order on the store: 02, 04, 03, 05, 01, 06 (lead with the recording screen).

## App Privacy (the "nutrition label")

- "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
- Result shown on the store: **Data Not Collected**.
- Matches `FourTrack/Resources/PrivacyInfo.xcprivacy` (no tracking, no collected data types).

## Age Rating

Answer the questionnaire as follows. The result is **4+**.

| Question | Answer |
|---|---|
| Parental controls | No |
| Age assurance | No |
| Unrestricted web access | No |
| User-generated content (shared with other users in the app) | No |
| Messaging and chat | No |
| Advertising | No |
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Prolonged graphic or sadistic realistic violence | None |
| Profanity or crude humor | None |
| Mature or suggestive themes | None |
| Horror or fear themes | None |
| Medical or treatment information | None |
| Alcohol, tobacco or drug use or references | None |
| Sexual content or nudity | None |
| Graphic sexual content and nudity | None |
| Gambling (simulated) | None |
| Gambling (real money) | No |
| Contests | None |
| Loot boxes | No |
| Health or wellness topics | No |
| Guns or other weapons | None |

Why no user-generated content: what people record stays on their device, and exporting goes through the iOS share sheet to apps they choose; nobody sees anyone else's content inside Four-Track.

## Export compliance

Already answered in the build (`ITSAppUsesNonExemptEncryption = NO`): the app uses no encryption beyond what iOS provides.

## Review notes (App Review Information → Notes)

No account or login is needed. To try it: tap the red record button on the projects list, play or sing for a few seconds, tap stop, then tap "+" (Add Track 2) and record a second part while the first plays. Export is in the ⋯ menu. Drum pads: switch the project to Full mode (⋯ → Simple Mode), then "+" → Drum Track. The microphone is used only to record.
