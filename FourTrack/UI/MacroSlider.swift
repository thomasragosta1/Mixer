import SwiftUI
import FourTrackCore

/// Macro slider (Compressor, Cleanup, Space, Warmth): 0...1, fill grows from
/// the low end; double tap resets to the macro's default.
struct MacroSlider: View {
    let label: String
    @Binding var value: Double
    var defaultValue: Double = 0
    var axis: SliderAxis = .horizontal
    /// Developer Mode values no longer match this slider's curve.
    var isCustom = false
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        SliderCore(
            value: $value,
            range: 0...1,
            fillOrigin: 0,
            resetValue: defaultValue,
            axis: axis,
            dimmed: isCustom,
            onEditingChanged: onEditingChanged
        )
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(isCustom ? "Custom" : SliderSpeech.percent(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }
}
