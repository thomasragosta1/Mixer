import Foundation

/// Grid sizes for drum quantize.
public enum QuantizeDivision: String, Codable, CaseIterable, Sendable, Identifiable {
    case quarter, eighth, sixteenth, thirtySecond, eighthTriplet, sixteenthTriplet
    /// Shuffle / swing: two notes per beat (or per eighth), the second one
    /// late, on the last third. What most swung grooves use, where a triplet
    /// grid would also allow the middle third that the groove never plays.
    case eighthSwing, sixteenthSwing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .quarter: return "1/4"
        case .eighth: return "1/8"
        case .sixteenth: return "1/16"
        case .thirtySecond: return "1/32"
        case .eighthTriplet: return "1/8T"
        case .sixteenthTriplet: return "1/16T"
        case .eighthSwing: return "1/8 Swing"
        case .sixteenthSwing: return "1/16 Swing"
        }
    }

    /// Short form for the Q chip.
    public var shortLabel: String {
        switch self {
        case .eighthSwing: return "1/8S"
        case .sixteenthSwing: return "1/16S"
        default: return label
        }
    }

    /// Grids in menu order: straight, swing, triplet.
    public static let menuOrder: [QuantizeDivision] = [.quarter, .eighth, .sixteenth, .thirtySecond, .eighthSwing, .sixteenthSwing, .eighthTriplet, .sixteenthTriplet]

    /// Swing grids: the pair length in quarter notes (a beat, or an eighth).
    var swingPairQuarters: Double? {
        switch self {
        case .eighthSwing: return 1
        case .sixteenthSwing: return 0.5
        default: return nil
        }
    }

    /// Grid step as a fraction of a quarter note.
    var quarters: Double {
        switch self {
        case .quarter: return 1
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .thirtySecond: return 0.125
        case .eighthTriplet: return 1.0 / 3
        case .sixteenthTriplet: return 1.0 / 6
        case .eighthSwing: return 0.5
        case .sixteenthSwing: return 0.25
        }
    }
}

/// Non-destructive quantize for a drum track: the hits keep their played
/// timing; only playback and the rendered audio snap to the grid. The grid
/// uses the tempo from when quantize was turned on, so later tempo changes
/// don't drag the drums away from the other tracks.
public struct QuantizeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var division: QuantizeDivision
    /// Tempo and beat unit the grid is built on.
    public var bpm: Double
    public var beatUnit: Int
    /// How far hits move toward the grid: 1 = all the way, 0.5 = halfway,
    /// keeping some of the played feel.
    public var strength: Double

    /// Where the late note of a swing pair sits, as a fraction of the pair:
    /// 2/3 is triplet (shuffle) swing.
    public static let swingRatio = 2.0 / 3
    public static let strengths: [Double] = [1, 0.75, 0.5]

    public init(enabled: Bool = false, division: QuantizeDivision = .sixteenth, bpm: Double = MetronomeSettings.defaultBPM, beatUnit: Int = 4, strength: Double = 1) {
        self.enabled = enabled
        self.division = division
        self.bpm = bpm
        self.beatUnit = beatUnit
        self.strength = strength
    }

    enum CodingKeys: String, CodingKey { case enabled, division, bpm, beatUnit, strength }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        division = (try? c.decodeIfPresent(QuantizeDivision.self, forKey: .division)) ?? nil ?? .sixteenth
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? MetronomeSettings.defaultBPM
        beatUnit = try c.decodeIfPresent(Int.self, forKey: .beatUnit) ?? 4
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? 1
    }

    private var quarterSeconds: Double {
        // In x/8 the BPM counts eighth notes, so a quarter note is two beats.
        60 / max(1, bpm) * Double(beatUnit) / 4
    }

    /// The nearest grid line to `time`, and an index identifying it.
    public func gridLine(near time: Double) -> (time: Double, slot: Int) {
        if let pairQuarters = division.swingPairQuarters {
            let pair = quarterSeconds * pairQuarters
            let k = (time / pair).rounded(.down)
            let candidates = [(k * pair, 0), (k * pair + pair * Self.swingRatio, 1), ((k + 1) * pair, 0)]
            let best = candidates.min { abs($0.0 - time) < abs($1.0 - time) }!
            let pairIndex = Int(k) + (best.0 > k * pair + pair * Self.swingRatio ? 1 : 0)
            return (best.0, pairIndex * 2 + best.1)
        }
        let grid = gridSeconds
        let slot = Int((time / grid).rounded())
        return (Double(slot) * grid, slot)
    }

    /// Grid step in seconds. The grid starts at timeline 0, like the click.
    public var gridSeconds: Double {
        quarterSeconds * division.quarters
    }

    /// Hits moved toward the grid (all the way at strength 1). Two hits of the
    /// same pad nearest the same grid line become one (the louder), so quantize
    /// never doubles a hit.
    public func apply(to hits: [DrumHit]) -> [DrumHit] {
        guard enabled else { return hits }
        let pull = min(max(strength, 0), 1)
        var best: [String: DrumHit] = [:]
        var order: [String] = []
        for hit in hits {
            let line = gridLine(near: hit.time)
            let slot = line.slot
            var snapped = hit
            snapped.time = max(0, hit.time + (line.time - hit.time) * pull)
            let key = "\(hit.pad)@\(slot)"
            if let existing = best[key] {
                if snapped.velocity > existing.velocity { best[key] = snapped }
            } else {
                best[key] = snapped
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }.sorted { $0.time < $1.time }
    }
}

extension Track {
    /// The hits as they sound: quantized when quantize is on.
    public var playableDrumHits: [DrumHit] { quantize.apply(to: drumHits) }
}
