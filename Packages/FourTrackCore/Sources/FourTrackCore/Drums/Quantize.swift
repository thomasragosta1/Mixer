import Foundation

/// Grid sizes for drum quantize.
public enum QuantizeDivision: String, Codable, CaseIterable, Sendable, Identifiable {
    case quarter, eighth, sixteenth, thirtySecond, eighthTriplet, sixteenthTriplet

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .quarter: return "1/4"
        case .eighth: return "1/8"
        case .sixteenth: return "1/16"
        case .thirtySecond: return "1/32"
        case .eighthTriplet: return "1/8T"
        case .sixteenthTriplet: return "1/16T"
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

    public init(enabled: Bool = false, division: QuantizeDivision = .sixteenth, bpm: Double = MetronomeSettings.defaultBPM, beatUnit: Int = 4) {
        self.enabled = enabled
        self.division = division
        self.bpm = bpm
        self.beatUnit = beatUnit
    }

    /// Grid step in seconds. The grid starts at timeline 0, like the click.
    public var gridSeconds: Double {
        // In x/8 the BPM counts eighth notes, so a quarter note is two beats.
        let quarterSeconds = 60 / max(1, bpm) * Double(beatUnit) / 4
        return quarterSeconds * division.quarters
    }

    /// Hits snapped to the grid. Two hits of the same pad landing on the same
    /// grid line become one (the louder), so quantize never doubles a hit.
    public func apply(to hits: [DrumHit]) -> [DrumHit] {
        guard enabled else { return hits }
        let grid = gridSeconds
        var best: [String: DrumHit] = [:]
        var order: [String] = []
        for hit in hits {
            let slot = Int((hit.time / grid).rounded())
            var snapped = hit
            snapped.time = max(0, Double(slot) * grid)
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
