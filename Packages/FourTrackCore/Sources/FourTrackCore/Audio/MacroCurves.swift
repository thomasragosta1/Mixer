import Foundation

/// Every macro slider mapping lives here as a pure function, so curves are
/// easy to tune by ear and to unit test. Slider values are stored in the
/// project; these functions turn them into DSP parameters.
public enum MacroCurves {

    // MARK: - Volume

    /// Slider position of unity gain (0 dB). The volume fader has a detent here.
    public static let volumeUnitySlider = 0.75
    public static let volumeMaxDB = 6.0
    /// Exponent of the audio taper below unity: gain = (s / 0.75)^3.
    static let volumeTaperExponent = 3.0

    /// 0 = -inf (mute), 0.75 = 0 dB, 1.0 = +6 dB.
    public static func volumeDB(_ slider: Double) -> Double {
        let s = clamp(slider, 0, 1)
        if s <= 0 { return -.infinity }
        if s <= volumeUnitySlider {
            return 20 * volumeTaperExponent * log10(s / volumeUnitySlider)
        }
        return volumeMaxDB * (s - volumeUnitySlider) / (1 - volumeUnitySlider)
    }

    /// Linear amplitude for a volume slider value.
    public static func volumeGain(_ slider: Double) -> Double {
        let db = volumeDB(slider)
        return db == -.infinity ? 0 : dbToGain(db)
    }

    /// Inverse of `volumeDB`, used for VoiceOver adjustments and Developer Mode entry.
    public static func volumeSlider(forDB db: Double) -> Double {
        if db == -.infinity { return 0 }
        if db <= 0 {
            return clamp(volumeUnitySlider * pow(10, db / (20 * volumeTaperExponent)), 0, volumeUnitySlider)
        }
        return clamp(volumeUnitySlider + min(db, volumeMaxDB) / volumeMaxDB * (1 - volumeUnitySlider), volumeUnitySlider, 1)
    }

    // MARK: - EQ

    public static let eqMaxDB = 12.0
    public static let eqLowFrequency = 120.0
    public static let eqMidFrequency = 1_200.0
    public static let eqMidBandwidthOctaves = 1.5
    public static let eqHighFrequency = 8_000.0
    /// Nominal shelf "bandwidth" passed to AVAudioUnitEQ; shelves ignore it.
    static let shelfBandwidth = 1.0

    /// -1...1 maps linearly to -12...+12 dB.
    public static func eqGainDB(_ slider: Double) -> Double {
        clamp(slider, -1, 1) * eqMaxDB
    }

    public static func eqSlider(forDB db: Double) -> Double {
        clamp(db / eqMaxDB, -1, 1)
    }

    public static func eqBands(low: Double, mid: Double, high: Double) -> [EQBandParams] {
        [
            EQBandParams(kind: .lowShelf, frequency: eqLowFrequency, gainDB: eqGainDB(low), bandwidthOctaves: shelfBandwidth),
            EQBandParams(kind: .parametric, frequency: eqMidFrequency, gainDB: eqGainDB(mid), bandwidthOctaves: eqMidBandwidthOctaves),
            EQBandParams(kind: .highShelf, frequency: eqHighFrequency, gainDB: eqGainDB(high), bandwidthOctaves: shelfBandwidth),
        ]
    }

    // MARK: - Compressor

    /// Anchor rows from the spec, interpolated piecewise-linearly.
    static let compressorAnchors: [(slider: Double, params: CompressorParams)] = [
        (0.0, CompressorParams(thresholdDB: 0, headroomDB: 20, attackSeconds: 0.010, releaseSeconds: 0.15, makeupGainDB: 0)),
        (0.5, CompressorParams(thresholdDB: -18, headroomDB: 8, attackSeconds: 0.008, releaseSeconds: 0.12, makeupGainDB: 4)),
        (1.0, CompressorParams(thresholdDB: -30, headroomDB: 3, attackSeconds: 0.003, releaseSeconds: 0.08, makeupGainDB: 8)),
    ]

    public static func compressor(_ slider: Double) -> CompressorParams {
        let s = clamp(slider, 0, 1)
        let anchors = compressorAnchors
        var lower = anchors[0]
        var upper = anchors[anchors.count - 1]
        for i in 0..<(anchors.count - 1) where s >= anchors[i].slider && s <= anchors[i + 1].slider {
            lower = anchors[i]
            upper = anchors[i + 1]
            break
        }
        let span = upper.slider - lower.slider
        let t = span > 0 ? (s - lower.slider) / span : 0
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return CompressorParams(
            thresholdDB: lerp(lower.params.thresholdDB, upper.params.thresholdDB),
            headroomDB: lerp(lower.params.headroomDB, upper.params.headroomDB),
            attackSeconds: lerp(lower.params.attackSeconds, upper.params.attackSeconds),
            releaseSeconds: lerp(lower.params.releaseSeconds, upper.params.releaseSeconds),
            makeupGainDB: lerp(lower.params.makeupGainDB, upper.params.makeupGainDB)
        )
    }

    // MARK: - Space

    public static let spaceMaxWet = 35.0
    public static let spacePreset: ReverbPresetChoice = .mediumRoom

    /// Gentle curve (slider squared) so the first half of the travel is subtle. Never fully wet.
    public static func spaceWetDryMix(_ slider: Double) -> Double {
        let s = clamp(slider, 0, 1)
        return spaceMaxWet * s * s
    }

    public static func reverb(_ slider: Double) -> ReverbParams {
        ReverbParams(preset: spacePreset, wetDryMix: spaceWetDryMix(slider))
    }

    // MARK: - Warmth (post-v1, behind a feature flag)

    public struct WarmthParams: Equatable, Sendable {
        public var wetDryMix: Double
        public var preGainDB: Double
        public var outputTrimDB: Double
    }

    public static func warmth(_ slider: Double) -> WarmthParams {
        let s = clamp(slider, 0, 1)
        let wet = 25 * s
        let pre = 6 * s
        // Compensate the added drive in proportion to how much of it is audible.
        let trim = -pre * (0.5 + 0.5 * wet / 25)
        return WarmthParams(wetDryMix: wet, preGainDB: pre, outputTrimDB: trim)
    }

    // MARK: - Cleanup

    /// Blend between the original take and its full-strength Cleanup render.
    /// Returns linear gains for the dry (original) and wet (cleaned) players.
    /// The two signals are time-aligned and highly correlated, so a linear
    /// (equal-gain) crossfade keeps loudness steady.
    public static func cleanupBlend(_ slider: Double) -> (dry: Double, wet: Double) {
        let s = clamp(slider, 0, 1)
        return (1 - s, s)
    }

    // MARK: - Metronome

    public static func metronomeGain(_ slider: Double) -> Double {
        let s = clamp(slider, 0, 1)
        return s * s
    }

    // MARK: - Helpers

    public static func dbToGain(_ db: Double) -> Double { pow(10, db / 20) }

    public static func gainToDB(_ gain: Double) -> Double {
        gain <= 0 ? -.infinity : 20 * log10(gain)
    }

    @inline(__always)
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v.isNaN ? lo : min(max(v, lo), hi)
    }
}

/// Spoken values for VoiceOver ("Low, plus 3 decibels"; "Compressor, 40 percent").
public enum SliderSpeech {
    public static func decibels(_ db: Double) -> String {
        if db == -.infinity { return "silent" }
        let rounded = Int(db.rounded())
        if rounded == 0 { return "0 decibels" }
        return "\(rounded > 0 ? "plus" : "minus") \(abs(rounded)) decibels"
    }

    public static func percent(_ value: Double) -> String {
        "\(Int((MacroCurves.clamp(value, 0, 1) * 100).rounded())) percent"
    }

    /// Short visual label, e.g. "+3 dB", "-inf dB".
    public static func shortDB(_ db: Double) -> String {
        if db == -.infinity { return "-∞ dB" }
        let r = (db * 10).rounded() / 10
        if abs(r) < 0.05 { return "0 dB" }
        return (r > 0 ? "+" : "") + String(format: "%.1f dB", r)
    }
}
