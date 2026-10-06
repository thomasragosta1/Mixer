import SwiftUI
import UIKit
import FourTrackCore

/// Press and hold a drum pad: its sound settings, mixer-style, in a bubble
/// tinted with the pad's colour. Moves are heard on the pads right away (and
/// each slider plays the pad when you let go) but only saved with the big
/// Apply button at the bottom; swiping the bubble away discards them.
/// Press and hold "Hold to Compare" to hear the kit's original sound; let go
/// to go back to yours.
/// The small Revert button at the top asks "Are you sure?" on the first tap
/// and reverts on the second; a tap anywhere else (or any change) cancels it.
struct PadSettingsSheet: View {
    @Bindable var model: ProjectViewModel
    let trackIndex: Int
    let pad: Int
    @State private var confirmingRevert = false
    @State private var draft: PadSettings
    @State private var applied = false
    /// While "Hold to Compare" is held: the pads play the kit's original sound.
    @State private var hearingOriginal = false
    @Environment(\.dismiss) private var dismiss

    init(model: ProjectViewModel, trackIndex: Int, pad: Int) {
        self.model = model
        self.trackIndex = trackIndex
        self.pad = pad
        let pads = model.project.tracks[trackIndex].padSettings
        _draft = State(initialValue: pads.indices.contains(pad) ? pads[pad] : .default)
    }

    private var track: Track { model.project.tracks[trackIndex] }
    private var saved: PadSettings {
        track.padSettings.indices.contains(pad) ? track.padSettings[pad] : .default
    }
    private var settings: PadSettings { draft }
    private var color: Color { DrumPadGrid.color(track.drumKit.family(of: pad)) }
    private var name: String { track.drumKit.padNames[pad] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            compareButton

            VStack(alignment: .leading, spacing: 18) {
            row("Volume", volumeText) {
                SliderCore(
                    value: binding(\.volume),
                    range: 0...1,
                    fillOrigin: 0,
                    detents: [MacroCurves.volumeUnitySlider],
                    detentRadius: 0.02,
                    resetValue: MacroCurves.volumeUnitySlider,
                    tint: color,
                    onEditingChanged: preview
                )
                .accessibilityElement()
                .accessibilityLabel("\(name) volume")
                .accessibilityValue(volumeText)
                .accessibilityAdjustableAction { adjust(\.volume, $0, step: 0.02, range: 0...1) }
            }
            if !model.isSimple {
            row("Tune", tuneText) {
                SliderCore(
                    value: binding(\.tune),
                    range: -1...1,
                    fillOrigin: 0,
                    detents: [0],
                    resetValue: 0,
                    tint: color,
                    onEditingChanged: preview
                )
                .accessibilityElement()
                .accessibilityLabel("\(name) tune")
                .accessibilityValue(tuneText)
                .accessibilityAdjustableAction { adjust(\.tune, $0, step: 1 / PadSettings.tuneRangeSemitones, range: -1...1) }
            }
            row("Decay", decayText) {
                SliderCore(
                    value: binding(\.decay),
                    range: 0...1,
                    fillOrigin: 0,
                    detents: [1],
                    resetValue: 1,
                    tint: color,
                    onEditingChanged: preview
                )
                .accessibilityElement()
                .accessibilityLabel("\(name) decay")
                .accessibilityValue(decayText)
                .accessibilityAdjustableAction { adjust(\.decay, $0, step: 0.05, range: 0...1) }
            }
            }
            row("Tone", toneText) {
                SliderCore(
                    value: binding(\.tone),
                    range: -1...1,
                    fillOrigin: 0,
                    detents: [0],
                    resetValue: 0,
                    tint: color,
                    onEditingChanged: preview
                )
                .accessibilityElement()
                .accessibilityLabel("\(name) tone")
                .accessibilityValue(toneText)
                .accessibilityAdjustableAction { adjust(\.tone, $0, step: 0.05, range: -1...1) }
            }
            }
            // While comparing, your settings step back: what you hear is the original.
            .opacity(hearingOriginal ? 0.3 : 1)
            .allowsHitTesting(!hearingOriginal)
            .animation(.easeOut(duration: 0.15), value: hearingOriginal)

            Spacer(minLength: 0)
            applyButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        // A tap on empty space cancels a pending revert.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { cancelRevert() })
        .onChange(of: draft) { _, new in
            cancelRevert()
            // Moving a slider always goes back to hearing your version.
            if hearingOriginal { hearingOriginal = false }
            model.previewPadSettings(track: trackIndex, pad: pad, new)
        }
        .onChange(of: hearingOriginal) { _, original in
            model.previewPadSettings(track: trackIndex, pad: pad, original ? .default : draft)
            model.hitPad(pad)
        }
        .onDisappear {
            if !applied { model.endPadPreview() }
        }
        .presentationDetents([.height(model.isSimple ? 380 : 556)])
        .presentationCornerRadius(34)
        .presentationDragIndicator(.visible)
        .presentationBackground {
            ZStack {
                Color(uiColor: .systemBackground)
                color.opacity(0.32)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.title2.bold())
                Text(track.drumKit.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            revertButton
            Button {
                cancelRevert()
                model.hitPad(pad)
            } label: {
                Image(systemName: "play.fill")
                    .font(.body)
                    .frame(width: 24, height: 24)
            }
            .glassButton()
            .tint(color)
            .accessibilityLabel("Play \(name)")
        }
    }

    /// Press and hold to hear the kit's original sound (the pad plays at once,
    /// and the pads on screen play it too while held); let go to hear yours
    /// again. Only shown once the sound has been changed.
    private var compareButton: some View {
        HStack(spacing: 8) {
            Image(systemName: hearingOriginal ? "ear.fill" : "ear")
            Text(hearingOriginal ? "Original" : "Hold to Compare")
                .contentTransition(.opacity)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(hearingOriginal ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(
            Capsule().fill(hearingOriginal ? color : Color(uiColor: .tertiarySystemFill))
        )
        .contentShape(Capsule())
        .scaleEffect(hearingOriginal ? 0.97 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: hearingOriginal)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !hearingOriginal else { return }
                    cancelRevert()
                    Haptics.hold()
                    hearingOriginal = true
                }
                .onEnded { _ in hearingOriginal = false }
        )
        .opacity(draft.isDefault ? 0 : 1)
        .allowsHitTesting(!draft.isDefault)
        .accessibilityElement()
        .accessibilityLabel("Compare with original")
        .accessibilityHint("Plays the kit's original sound. Activate again to hear yours.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { hearingOriginal.toggle() }
        .accessibilityHidden(draft.isDefault)
    }

    /// Big button at the bottom: saves the sound and closes.
    private var applyButton: some View {
        Button {
            cancelRevert()
            applied = true
            model.applyPadSettings(track: trackIndex, pad: pad, draft)
            dismiss()
        } label: {
            Text(draft == saved ? "Done" : "Apply")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .prominentGlassButton()
        .controlSize(.large)
        .tint(color)
        .accessibilityHint(draft == saved ? "Closes" : "Saves this sound and updates the drum track")
    }

    /// Small button at the top. First tap: "Are you sure?". Second tap: back to
    /// the kit's own sound, saved at once.
    private var revertButton: some View {
        Button {
            if confirmingRevert {
                draft = .default
                model.revertPad(track: trackIndex, pad: pad)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                confirmingRevert = false
            } else {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { confirmingRevert = true }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            Text(confirmingRevert ? "Are you sure?" : "Revert")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 4)
        }
        .glassButton()
        .controlSize(.small)
        .tint(confirmingRevert ? .red : color)
        .disabled(saved.isDefault && draft.isDefault && !confirmingRevert)
        .accessibilityLabel(confirmingRevert ? "Are you sure?" : "Revert to Default")
        .accessibilityHint(confirmingRevert ? "Tap again to revert. Tap anywhere else to cancel." : "Asks before reverting.")
    }

    private func row<S: View>(_ title: String, _ value: String, @ViewBuilder slider: () -> S) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            slider()
        }
    }

    // MARK: Values

    private func binding(_ key: WritableKeyPath<PadSettings, Double>) -> Binding<Double> {
        Binding(
            get: { settings[keyPath: key] },
            set: { value in draft[keyPath: key] = value }
        )
    }

    private func adjust(_ key: WritableKeyPath<PadSettings, Double>, _ direction: AccessibilityAdjustmentDirection, step: Double, range: ClosedRange<Double>) {
        let delta = direction == .increment ? step : -step
        draft[keyPath: key] = min(max(draft[keyPath: key] + delta, range.lowerBound), range.upperBound)
    }

    /// Plays the pad when a slider is let go, so each change can be heard.
    private func preview(_ editing: Bool) {
        if !editing { model.hitPad(pad) }
    }

    private func cancelRevert() {
        if confirmingRevert {
            withAnimation(.easeOut(duration: 0.2)) { confirmingRevert = false }
        }
    }

    private var volumeText: String { SliderSpeech.shortDB(MacroCurves.volumeDB(settings.volume)) }

    private var tuneText: String {
        let st = Int(settings.semitones)
        return st == 0 ? "0 st" : String(format: "%+d st", st)
    }

    private var decayText: String {
        settings.decay >= 0.995 ? "Natural" : "\(Int((settings.decay * 100).rounded()))%"
    }

    private var toneText: String {
        if abs(settings.tone) < 0.005 { return "Neutral" }
        let pct = Int((abs(settings.tone) * 100).rounded())
        return settings.tone < 0 ? "Darker \(pct)%" : "Brighter \(pct)%"
    }
}
