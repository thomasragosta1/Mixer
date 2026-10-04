import SwiftUI
import FourTrackCore

/// Developer Mode: the exploded parameters behind each macro for one track.
/// Editing a section stores an override; moving that macro in the strip hands
/// control back to the curve.
struct DevTrackControlsView: View {
    @Bindable var model: ProjectViewModel
    let index: Int
    @Environment(\.dismiss) private var dismiss

    private var track: Track { model.project.tracks[index] }

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                compressorSection
                eqSection
                reverbSection
                Section {
                    Button("Reset to Macros", role: .destructive) {
                        model.resetDevOverrides(index)
                    }
                    .disabled(track.devOverrides == nil)
                } footer: {
                    Text("Overrides are kept when Developer Mode is off. The strip shows \"Custom\" while they differ from the macro.")
                }
            }
            .navigationTitle(track.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Sections

    private var inputSection: some View {
        Section("Input") {
            ParamSlider(
                title: "Input gain",
                value: track.inputGainDB,
                range: DevParams.inputGainRange,
                format: { SliderSpeech.shortDB($0) },
                resetValue: 0
            ) { v in
                model.editDevParams(index) { p, _ in p.inputGainDB = abs(v) < 0.05 ? nil : v }
            }
        }
    }

    private var compressorSection: some View {
        let c = track.resolvedCompressor
        return Section {
            ParamSlider(title: "Threshold", value: c.thresholdDB, range: CompressorParams.thresholdRange, format: { String(format: "%.1f dB", $0) }, resetValue: MacroCurves.compressor(track.compressor).thresholdDB) { v in
                editCompressor { $0.thresholdDB = v }
            }
            ParamSlider(title: "Ratio", value: c.ratio, range: CompressorParams.ratioRange, logarithmic: true, format: { String(format: "%.1f:1", $0) }, resetValue: MacroCurves.compressor(track.compressor).ratio) { v in
                editCompressor { $0.ratio = v }
            }
            ParamSlider(title: "Knee", value: c.kneeDB, range: CompressorParams.kneeRange, format: { String(format: "%.1f dB", $0) }, resetValue: MacroCurves.compressor(track.compressor).kneeDB) { v in
                editCompressor { $0.kneeDB = v }
            }
            ParamSlider(title: "Attack", value: c.attackSeconds, range: CompressorParams.attackRange, logarithmic: true, format: { String(format: "%.1f ms", $0 * 1000) }, resetValue: MacroCurves.compressor(track.compressor).attackSeconds) { v in
                editCompressor { $0.attackSeconds = v }
            }
            ParamSlider(title: "Release", value: c.releaseSeconds, range: CompressorParams.releaseRange, logarithmic: true, format: { String(format: "%.0f ms", $0 * 1000) }, resetValue: MacroCurves.compressor(track.compressor).releaseSeconds) { v in
                editCompressor { $0.releaseSeconds = v }
            }
            ParamSlider(title: "Makeup", value: c.makeupGainDB, range: CompressorParams.makeupRange, format: { SliderSpeech.shortDB($0) }, resetValue: MacroCurves.compressor(track.compressor).makeupGainDB) { v in
                editCompressor { $0.makeupGainDB = v }
            }
        } header: {
            Text("Compressor\(track.isCompressorCustom ? " · Custom" : "")")
        }
    }

    private var eqSection: some View {
        let bands = track.resolvedEQ
        let names = ["Low shelf", "Mid", "High shelf"]
        return Section {
            ForEach(Array(bands.enumerated()), id: \.offset) { i, band in
                VStack(alignment: .leading, spacing: 2) {
                    Text(names[min(i, names.count - 1)]).font(.subheadline.weight(.semibold))
                    ParamSlider(title: "Frequency", value: band.frequency, range: EQBandParams.frequencyRange, logarithmic: true, format: Self.hertz, resetValue: MacroCurves.eqBands(low: 0, mid: 0, high: 0)[i].frequency) { v in
                        editEQ(i) { $0.frequency = v }
                    }
                    ParamSlider(title: "Gain", value: band.gainDB, range: EQBandParams.gainRange, centered: true, format: { SliderSpeech.shortDB($0) }, resetValue: 0) { v in
                        editEQ(i) { $0.gainDB = v }
                    }
                    if band.kind == .parametric {
                        ParamSlider(title: "Bandwidth", value: band.bandwidthOctaves, range: EQBandParams.bandwidthRange, logarithmic: true, format: { String(format: "%.2f oct", $0) }, resetValue: MacroCurves.eqMidBandwidthOctaves) { v in
                            editEQ(i) { $0.bandwidthOctaves = v }
                        }
                    }
                }
            }
        } header: {
            Text("EQ\(track.isEQCustom ? " · Custom" : "")")
        }
    }

    private var reverbSection: some View {
        let r = track.resolvedReverb
        return Section {
            Picker("Preset", selection: Binding(
                get: { r.preset },
                set: { preset in model.editDevParams(index) { p, t in
                    var current = p.reverb ?? MacroCurves.reverb(t.space)
                    current.preset = preset
                    p.reverb = current
                } }
            )) {
                ForEach(ReverbPresetChoice.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            ParamSlider(title: "Wet mix", value: r.wetDryMix, range: 0...100, format: { String(format: "%.0f%%", $0) }, resetValue: MacroCurves.spaceWetDryMix(track.space)) { v in
                model.editDevParams(index) { p, t in
                    var current = p.reverb ?? MacroCurves.reverb(t.space)
                    current.wetDryMix = v
                    p.reverb = current
                }
            }
        } header: {
            Text("Space\(track.isSpaceCustom ? " · Custom" : "")")
        }
    }

    // MARK: Editing helpers

    private func editCompressor(_ change: @escaping (inout CompressorParams) -> Void) {
        model.editDevParams(index) { p, t in
            var c = p.compressor ?? MacroCurves.compressor(t.compressor)
            change(&c)
            p.compressor = c
        }
    }

    private func editEQ(_ band: Int, _ change: @escaping (inout EQBandParams) -> Void) {
        model.editDevParams(index) { p, t in
            var bands = p.eq ?? MacroCurves.eqBands(low: t.eqLow, mid: t.eqMid, high: t.eqHigh)
            guard bands.indices.contains(band) else { return }
            change(&bands[band])
            p.eq = bands
        }
    }

    static func hertz(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1f kHz", v / 1000) : String(format: "%.0f Hz", v)
    }
}

/// Labeled fader for a raw parameter, with optional log mapping.
struct ParamSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var logarithmic = false
    var centered = false
    let format: (Double) -> String
    let resetValue: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(format(value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            SliderCore(
                value: Binding(get: { toUnit(value) }, set: { onChange(fromUnit($0)) }),
                range: 0...1,
                fillOrigin: centered ? toUnit(0) : 0,
                detents: centered ? [toUnit(0)] : [],
                resetValue: toUnit(resetValue)
            )
        }
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let u = toUnit(value)
            switch direction {
            case .increment: onChange(fromUnit(min(1, u + 0.02)))
            case .decrement: onChange(fromUnit(max(0, u - 0.02)))
            @unknown default: break
            }
        }
    }

    private func toUnit(_ v: Double) -> Double {
        let c = min(max(v, range.lowerBound), range.upperBound)
        if logarithmic, range.lowerBound > 0 {
            return log(c / range.lowerBound) / log(range.upperBound / range.lowerBound)
        }
        return (c - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func fromUnit(_ u: Double) -> Double {
        if logarithmic, range.lowerBound > 0 {
            return range.lowerBound * pow(range.upperBound / range.lowerBound, u)
        }
        return range.lowerBound + u * (range.upperBound - range.lowerBound)
    }
}
