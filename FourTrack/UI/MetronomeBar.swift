import SwiftUI
import UIKit
import FourTrackCore

/// The metronome, kept to one row:
/// - the mode button cycles Click → Silent (beats shown, no sound) → Off,
/// - the time signature cycles 4/4 → 3/4 → 2/4 (press and hold for more),
/// - the arrows change the tempo by the project's step (press and hold for 1 BPM steps),
/// - the beat lights pulse in time whenever the metronome runs.
struct MetronomeBar: View {
    @Bindable var model: ProjectViewModel

    private var m: MetronomeSettings { model.project.metronome }

    var body: some View {
        HStack(spacing: 6) {
            modeButton
            signatureButton
                .opacity(m.enabled ? 1 : 0.45)
            TempoArrow(systemName: "chevron.left", label: "Slower") {
                model.nudgeTempo(-1, fine: $0)
            }
            VStack(spacing: -2) {
                Text("\(Int(m.bpm))")
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                Text("BPM")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38)
            .opacity(m.enabled ? 1 : 0.45)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tempo")
            .accessibilityValue("\(Int(m.bpm)) beats per minute")
            .accessibilityAdjustableAction { direction in
                model.nudgeTempo(direction == .increment ? 1 : -1, fine: false)
            }
            TempoArrow(systemName: "chevron.right", label: "Faster") {
                model.nudgeTempo(1, fine: $0)
            }
            previewButton
            Spacer(minLength: 2)
            if m.enabled || model.isPreviewingClick {
                BeatLights(
                    metronome: m,
                    clock: model.isPreviewingClick ? model.previewClock : model.clock,
                    anchor: { model.beatAnchor },
                    emphasized: m.mode == .visual
                )
                .frame(maxWidth: 64)
                .transition(.opacity)
            }
        }
        // Usable while recording too: switch the click on, or change tempo, mid-take.
        .disabled(model.isSaving)
        .animation(.easeOut(duration: 0.2), value: m.mode)
    }

    /// Plays the click on its own to try the tempo (not while the song plays).
    private var previewButton: some View {
        Button {
            model.toggleClickPreview()
        } label: {
            Image(systemName: model.isPreviewingClick ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(model.isPreviewingClick ? Color.white : Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Circle().fill(model.isPreviewingClick ? Color.accentColor : Color.accentColor.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(model.isPlaying || model.isRecording)
        .opacity(model.isPlaying || model.isRecording ? 0.4 : 1)
        .accessibilityLabel(model.isPreviewingClick ? "Stop click" : "Play click")
        .accessibilityHint("Plays the metronome on its own")
    }

    private var modeButton: some View {
        Button {
            model.cycleMetronomeMode()
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 6)
            .frame(width: 76, height: 32)
            .foregroundStyle(m.mode == .on ? Color.white : (m.mode == .visual ? Color.accentColor : Color.secondary))
            .background(Capsule().fill(m.mode == .on ? Color.accentColor : (m.mode == .visual ? Color.accentColor.opacity(0.16) : Color(uiColor: .tertiarySystemFill))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Metronome")
        .accessibilityValue(m.mode == .on ? "Click on" : (m.mode == .visual ? "Silent, beats shown" : "Off"))
        .accessibilityHint("Cycles click, silent and off")
    }

    private var icon: String {
        switch m.mode {
        case .on: return "metronome.fill"
        case .visual: return "eye.fill"
        case .off: return "metronome"
        }
    }

    private var title: String {
        switch m.mode {
        case .on: return "Click"
        case .visual: return "Silent"
        case .off: return "Off"
        }
    }

    /// Tap cycles the common signatures; press and hold opens the rest.
    private var signatureButton: some View {
        Menu {
            Section("Common") {
                ForEach(TimeSignature.quick, id: \.self) { sig in
                    Button(sig.label) { model.setTimeSignature(sig) }
                }
            }
            Section("More") {
                ForEach(TimeSignature.more, id: \.self) { sig in
                    Button(sig.label) { model.setTimeSignature(sig) }
                }
            }
        } label: {
            Text(m.timeSignature.label)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 46, height: 32)
                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                .contentShape(Capsule())
        } primaryAction: {
            model.cycleTimeSignature()
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in Haptics.hold() })
        .accessibilityLabel("Time signature")
        .accessibilityValue(m.timeSignature.label)
        .accessibilityHint("Tap to cycle 4/4, 3/4 and 2/4. Press and hold for more.")
    }
}

/// An arrow that steps on tap and repeats fine steps while held.
struct TempoArrow: View {
    let systemName: String
    let label: String
    /// Called with `fine: false` for a tap, `fine: true` for each repeat while held.
    let onStep: (Bool) -> Void
    @State private var holdTask: Task<Void, Never>?
    @State private var didRepeat = false
    @State private var pressed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .bold))
            .frame(width: 36, height: 32)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill).opacity(pressed ? 1 : 0.6)))
            .contentShape(Rectangle())
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard holdTask == nil else { return }
                        pressed = true
                        didRepeat = false
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            if !Task.isCancelled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                            var interval: UInt64 = 150_000_000
                            while !Task.isCancelled {
                                didRepeat = true
                                onStep(true)
                                UISelectionFeedbackGenerator().selectionChanged()
                                try? await Task.sleep(nanoseconds: interval)
                                interval = max(45_000_000, interval * 85 / 100)
                            }
                        }
                    }
                    .onEnded { _ in
                        holdTask?.cancel()
                        holdTask = nil
                        pressed = false
                        if !didRepeat {
                            onStep(false)
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onStep(false) }
    }
}

/// One light per beat; the current beat pulses (the downbeat in red).
struct BeatLights: View {
    let metronome: MetronomeSettings
    let clock: PlayheadClock
    /// The click's current grid anchor (it moves when the tempo changes mid-play).
    var anchor: () -> (seconds: Double, beat: Double) = { (0, 0) }
    /// Bigger lights when the metronome is silent and the lights are the only cue.
    var emphasized = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !clock.running)) { context in
            let position = clock.rawPosition(at: context.date)
            let a = anchor()
            let beats = a.beat + (position - a.seconds) * metronome.bpm / 60
            let whole = beats.rounded(.down)
            let n = Double(max(1, metronome.beatsPerBar))
            let beat = Int((whole.truncatingRemainder(dividingBy: n) + n).truncatingRemainder(dividingBy: n))
            let phase = beats - whole
            let count = max(1, metronome.beatsPerBar)
            let size: CGFloat = count > 6 ? 4 : (count > 4 ? 6 : (emphasized ? 10 : 8))
            HStack(spacing: count > 6 ? 1.5 : 4) {
                ForEach(0..<count, id: \.self) { i in
                    let active = clock.running && i == beat
                    Circle()
                        .fill(active ? (i == 0 ? Color.red : Color.accentColor) : Color.secondary.opacity(0.25))
                        .frame(width: size, height: size)
                        .scaleEffect(active ? 1 + 0.45 * (1 - phase) : 1)
                        .opacity(active ? 0.55 + 0.45 * (1 - phase) : 1)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
