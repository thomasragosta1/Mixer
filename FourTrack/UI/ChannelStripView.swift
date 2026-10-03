import SwiftUI
import FourTrackCore

/// One vertical channel strip. Top to bottom: name, Cleanup, Warmth (flag),
/// Space, Compressor, High, Mid, Low, Volume, M/S.
struct ChannelStripView: View {
    @Bindable var model: ProjectViewModel
    let index: Int
    var onShowDetails: () -> Void = {}

    static let macroHeight: CGFloat = 84
    static let faderHeight: CGFloat = 180

    private var track: Track { model.project.tracks[index] }
    private var showsWarmth: Bool { model.developerMode && model.settings.warmthEnabled }

    var body: some View {
        VStack(spacing: 10) {
            Text(track.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 28)

            cleanup

            if showsWarmth {
                macro("Warmth", value: track.warmth, set: { model.setWarmth(index, $0) })
            }

            macro("Space", value: track.space, isCustom: track.isSpaceCustom, set: { model.setSpace(index, $0) })

            macro("Comp", spokenName: "Compressor", value: track.compressor, defaultValue: Track.defaultCompressor, isCustom: track.isCompressorCustom, set: { model.setCompressor(index, $0) })

            eq("High", value: track.eqHigh) { model.setEQ(index, high: $0) }
            eq("Mid", value: track.eqMid) { model.setEQ(index, mid: $0) }
            eq("Low", value: track.eqLow) { model.setEQ(index, low: $0) }

            StripLabel(title: "Volume", value: SliderSpeech.shortDB(MacroCurves.volumeDB(track.volume)))
            HStack(spacing: 4) {
                VolumeFader(label: "\(track.name) volume", value: Binding(
                    get: { track.volume },
                    set: { model.setVolume(index, $0) }
                ), axis: .vertical)
                if model.developerMode {
                    MeterView(level: model.meterLevels[index]) { model.resetClip(index) }
                }
            }
            .frame(height: Self.faderHeight)

            VStack(spacing: 4) {
                ToggleChip(title: "M", isOn: track.mute, onColor: .orange, accessibilityName: "Mute \(track.name)") {
                    model.toggleMute(index)
                }
                ToggleChip(title: "S", isOn: track.solo, onColor: .yellow, accessibilityName: "Solo \(track.name)") {
                    model.toggleSolo(index)
                }
            }

            if model.developerMode {
                Button("Details", action: onShowDetails)
                    .font(.caption2)
                    .frame(minHeight: 44)
                    .accessibilityLabel("\(track.name) details")
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .opacity(model.project.isAudible(index) ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(track.name)
    }

    private var cleanup: some View {
        VStack(spacing: 4) {
            StripLabel(title: "Cleanup", value: SliderSpeech.percent(track.cleanup).replacingOccurrences(of: " percent", with: "%"))
            ZStack {
                MacroSlider(label: "\(track.name) Cleanup", value: Binding(
                    get: { track.cleanup },
                    set: { model.setCleanup(index, $0) }
                ), axis: .vertical)
                .disabled(track.isEmpty)
                if let progress = model.cleanupProgress[index] {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .padding(4)
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel("Cleaning up")
                        .accessibilityValue(SliderSpeech.percent(progress))
                }
            }
            .frame(height: Self.macroHeight)
        }
    }

    private func macro(_ title: String, spokenName: String? = nil, value: Double, defaultValue: Double = 0, isCustom: Bool = false, set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 4) {
            StripLabel(title: title, value: SliderSpeech.percent(value).replacingOccurrences(of: " percent", with: "%"), isCustom: isCustom)
            MacroSlider(
                label: "\(track.name) \(spokenName ?? title)",
                value: Binding(get: { value }, set: set),
                defaultValue: defaultValue,
                axis: .vertical,
                isCustom: isCustom
            )
            .frame(height: Self.macroHeight)
        }
    }

    private func eq(_ title: String, value: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 4) {
            StripLabel(title: title, value: SliderSpeech.shortDB(MacroCurves.eqGainDB(value)), isCustom: track.isEQCustom)
            CenteredSlider(
                label: "\(track.name) \(title)",
                value: Binding(get: { value }, set: set),
                axis: .vertical,
                dimmed: track.isEQCustom
            )
            .frame(height: Self.macroHeight)
        }
    }
}

/// Peak/RMS level meter with a sticky clip light (tap to reset).
struct MeterView: View {
    let level: MeterStore.Level
    let onResetClip: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Circle()
                .fill(level.clipped ? Color.red : Color(uiColor: .tertiarySystemFill))
                .frame(width: 8, height: 8)
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .bottom, endPoint: .top))
                        .frame(height: geo.size.height * Self.fraction(level.peak))
                        .opacity(0.35)
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .green, .yellow, .red], startPoint: .bottom, endPoint: .top))
                        .frame(height: geo.size.height * Self.fraction(level.rms))
                }
            }
            .frame(width: 6)
        }
        .frame(width: 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onResetClip)
        .accessibilityElement()
        .accessibilityLabel("Level")
        .accessibilityValue(level.clipped ? "Clipped" : SliderSpeech.decibels(MacroCurves.gainToDB(Double(level.peak))))
    }

    /// -60...0 dBFS mapped to 0...1.
    static func fraction(_ amplitude: Float) -> CGFloat {
        guard amplitude > 0 else { return 0 }
        let db = 20 * log10(Double(amplitude))
        return CGFloat(min(1, max(0, (db + 60) / 60)))
    }
}
