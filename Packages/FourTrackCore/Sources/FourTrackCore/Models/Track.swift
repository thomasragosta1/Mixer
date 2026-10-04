import Foundation

/// One of the four fixed tracks in a project. Stores slider values, not raw
/// DSP parameters, so future curve tuning improves old projects.
public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var index: Int
    public var name: String
    /// nil = empty track.
    public var audioFileName: String?
    /// Full-strength Cleanup render of `audioFileName`, blended by `cleanup`.
    public var cleanedFileName: String?
    public var mute: Bool
    public var solo: Bool
    /// 0...1 slider value, unity at 0.75.
    public var volume: Double
    /// -1...1 slider values.
    public var eqLow: Double
    public var eqMid: Double
    public var eqHigh: Double
    /// 0...1 slider values.
    public var compressor: Double
    public var space: Double
    public var warmth: Double
    public var cleanup: Double
    /// Cleanup amount to restore when the on/off button turns it back on.
    public var cleanupLevel: Double
    /// Exploded values edited in Developer Mode. Sections left nil follow the macro curves.
    public var devOverrides: DevParams?
    /// Length of the take in seconds (0 when empty). Cached so the list can show durations
    /// without opening audio files.
    public var durationSeconds: Double
    /// Audio route the take was recorded on, used to decide whether to offer Cleanup.
    public var lastRecordedRoute: AudioRouteKind?

    public var id: Int { index }

    public static let defaultCompressor = 0.3
    public static let defaultCleanupLevel = 0.6

    public var isCleanupOn: Bool { cleanup > 0 }

    public init(index: Int, name: String? = nil) {
        self.index = index
        self.name = name ?? "Track \(index + 1)"
        self.audioFileName = nil
        self.cleanedFileName = nil
        self.mute = false
        self.solo = false
        self.volume = MacroCurves.volumeUnitySlider
        self.eqLow = 0
        self.eqMid = 0
        self.eqHigh = 0
        self.compressor = Track.defaultCompressor
        self.space = 0
        self.warmth = 0
        self.cleanup = 0
        self.cleanupLevel = Track.defaultCleanupLevel
        self.devOverrides = nil
        self.durationSeconds = 0
        self.lastRecordedRoute = nil
    }

    public var isEmpty: Bool { audioFileName == nil }

    /// Effective parameters for the DSP chain: Developer Mode overrides where present,
    /// macro curves everywhere else.
    public var resolvedCompressor: CompressorParams {
        devOverrides?.compressor ?? MacroCurves.compressor(compressor)
    }

    public var resolvedEQ: [EQBandParams] {
        devOverrides?.eq ?? MacroCurves.eqBands(low: eqLow, mid: eqMid, high: eqHigh)
    }

    public var resolvedReverb: ReverbParams {
        devOverrides?.reverb ?? MacroCurves.reverb(space)
    }

    public var inputGainDB: Double { devOverrides?.inputGainDB ?? 0 }

    /// True when Developer Mode values no longer match what the simple slider would produce.
    public var isCompressorCustom: Bool {
        guard let o = devOverrides?.compressor else { return false }
        return !o.isApproximatelyEqual(to: MacroCurves.compressor(compressor))
    }

    public var isEQCustom: Bool {
        guard let o = devOverrides?.eq else { return false }
        let curve = MacroCurves.eqBands(low: eqLow, mid: eqMid, high: eqHigh)
        return o.count != curve.count || zip(o, curve).contains { !$0.isApproximatelyEqual(to: $1) }
    }

    public var isSpaceCustom: Bool {
        guard let o = devOverrides?.reverb else { return false }
        return !o.isApproximatelyEqual(to: MacroCurves.reverb(space))
    }

    enum CodingKeys: String, CodingKey {
        case index, name, audioFileName, cleanedFileName, mute, solo, volume
        case eqLow, eqMid, eqHigh, compressor, space, warmth, cleanup, cleanupLevel, devOverrides
        case durationSeconds, lastRecordedRoute
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let index = try c.decode(Int.self, forKey: .index)
        self.init(index: index)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? name
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        cleanedFileName = try c.decodeIfPresent(String.self, forKey: .cleanedFileName)
        mute = try c.decodeIfPresent(Bool.self, forKey: .mute) ?? false
        solo = try c.decodeIfPresent(Bool.self, forKey: .solo) ?? false
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        eqLow = try c.decodeIfPresent(Double.self, forKey: .eqLow) ?? 0
        eqMid = try c.decodeIfPresent(Double.self, forKey: .eqMid) ?? 0
        eqHigh = try c.decodeIfPresent(Double.self, forKey: .eqHigh) ?? 0
        compressor = try c.decodeIfPresent(Double.self, forKey: .compressor) ?? Track.defaultCompressor
        space = try c.decodeIfPresent(Double.self, forKey: .space) ?? 0
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        cleanup = try c.decodeIfPresent(Double.self, forKey: .cleanup) ?? 0
        cleanupLevel = try c.decodeIfPresent(Double.self, forKey: .cleanupLevel) ?? Track.defaultCleanupLevel
        devOverrides = try c.decodeIfPresent(DevParams.self, forKey: .devOverrides)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        lastRecordedRoute = try c.decodeIfPresent(AudioRouteKind.self, forKey: .lastRecordedRoute)
    }
}

/// Output route categories that get their own latency offset.
public enum AudioRouteKind: String, Codable, CaseIterable, Sendable {
    case speaker
    case wired
    case bluetooth
    case other

    public var displayName: String {
        switch self {
        case .speaker: return "Built-in speaker"
        case .wired: return "Wired headphones"
        case .bluetooth: return "Bluetooth"
        case .other: return "Other"
        }
    }
}
