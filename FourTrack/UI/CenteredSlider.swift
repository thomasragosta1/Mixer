import SwiftUI
import FourTrackCore

/// EQ band slider: -1...1, neutral at 0. Blue fill grows from the center
/// toward the thumb; light haptic tick and a small magnetic detent at 0;
/// double tap resets to 0.
struct CenteredSlider: View {
    let label: String
    @Binding var value: Double
    var axis: SliderAxis = .horizontal
    var dimmed = false
    var onEditingChanged: (Bool) -> Void = { _ in }

    /// One VoiceOver step = 1 dB.
    private var step: Double { 1 / MacroCurves.eqMaxDB }

    var body: some View {
        SliderCore(
            value: $value,
            range: -1...1,
            fillOrigin: 0,
            detents: [0],
            resetValue: 0,
            axis: axis,
            dimmed: dimmed,
            onEditingChanged: onEditingChanged
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(SliderSpeech.decibels(MacroCurves.eqGainDB(value)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + step)
            case .decrement: value = max(-1, value - step)
            @unknown default: break
            }
        }
    }
}
