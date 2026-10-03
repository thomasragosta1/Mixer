import SwiftUI
import FourTrackCore

/// Volume fader: 0...1 mapped to dB (0 = silent, 0.75 = 0 dB, 1 = +6 dB) with
/// a detent and haptic at unity.
struct VolumeFader: View {
    var label = "Volume"
    @Binding var value: Double
    var axis: SliderAxis = .horizontal
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        SliderCore(
            value: $value,
            range: 0...1,
            fillOrigin: 0,
            detents: [MacroCurves.volumeUnitySlider],
            detentRadius: 0.02,
            resetValue: MacroCurves.volumeUnitySlider,
            axis: axis,
            onEditingChanged: onEditingChanged
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(SliderSpeech.decibels(MacroCurves.volumeDB(value)))
        .accessibilityAdjustableAction { direction in
            // 1 dB steps around the useful range.
            let db = MacroCurves.volumeDB(value)
            let current = db == -.infinity ? -60 : db
            switch direction {
            case .increment:
                value = MacroCurves.volumeSlider(forDB: min(MacroCurves.volumeMaxDB, current + 1))
            case .decrement:
                value = current - 1 <= -60 ? 0 : MacroCurves.volumeSlider(forDB: current - 1)
            @unknown default: break
            }
        }
    }
}
