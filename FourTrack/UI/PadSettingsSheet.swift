import SwiftUI
import UIKit
import FourTrackCore

/// Press and hold a drum pad: its sound settings, mixer-style, in a bubble
/// tinted with the pad's colour. Every slider plays the pad when you let go.
/// "Revert to Default" asks "Are you sure?" on the first tap and reverts on
/// the second; a tap anywhere else (or any other change) cancels it.
struct PadSettingsSheet: View {
    @Bindable var model: ProjectViewModel
    let trackIndex: Int
    let pad: Int
    @State private var confirmingRevert = false
    @Environment(\.dismiss) private var dismiss

    private var track: Track { model.project.tracks[trackIndex] }
    private var settings: PadSettings {
        track.padSettings.indices.contains(pad) ? track.padSettings[pad] : .default
    }
    private var color: Color { DrumPadGrid.color(track.drumKit.family(of: pad)) }
    private var name: String { track.drumKit.padNames[pad] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

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

            revertButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        // A tap on empty space cancels a pending revert.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture { cancelRevert() })
        .onChange(of: settings) { _, _ in cancelRevert() }
        .presentationDetents([.height(500)])
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
            Button {
                cancelRevert()
                model.hitPad(pad)
            } label: {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .frame(width: 30, height: 30)
            }
            .glassButton()
            .tint(color)
            .accessibilityLabel("Play \(name)")
            Button("Done") {
                cancelRevert()
                dismiss()
            }
            .prominentGlassButton()
            .tint(color)
        }
    }

    private var revertButton: some View {
        VStack(spacing: 6) {
            Button {
                if confirmingRevert {
                    model.revertPad(track: trackIndex, pad: pad)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    confirmingRevert = false
                } else {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { confirmingRevert = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } label: {
                Text(confirmingRevert ? "Are you sure?" : "Revert to Default")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .prominentGlassButton()
            .tint(confirmingRevert ? .red : color)
            .disabled(settings.isDefault && !confirmingRevert)
            .accessibilityHint(confirmingRevert ? "Tap again to revert. Tap anywhere else to cancel." : "Asks before reverting.")

            Text(confirmingRevert ? "Tap again to revert. Tap anywhere else to cancel." : " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.top, 4)
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
            set: { value in
                var s = settings
                s[keyPath: key] = value
                model.setPadSettings(track: trackIndex, pad: pad, s)
            }
        )
    }

    private func adjust(_ key: WritableKeyPath<PadSettings, Double>, _ direction: AccessibilityAdjustmentDirection, step: Double, range: ClosedRange<Double>) {
        var s = settings
        let delta = direction == .increment ? step : -step
        s[keyPath: key] = min(max(s[keyPath: key] + delta, range.lowerBound), range.upperBound)
        model.setPadSettings(track: trackIndex, pad: pad, s)
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
