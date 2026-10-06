import Foundation

/// Balances the pads of every kit so they sit together the way a mixed drum
/// kit does, whatever level each sample was recorded or synthesized at.
/// Each one-shot is measured with ITU-R BS.1770 K-weighting (the loudness
/// curve behind LUFS) over its loudest 150 ms, then gained to a target for its
/// role: kick and snare up front, toms a little under, hats and shakers well
/// under, cymbals in between. Peaks are kept below full scale.
public enum DrumLevels {
    /// Loudness every kit's kick is set to (when its peak allows), in
    /// LUFS-style dB, so switching kits doesn't jump in level.
    static let kickLoudness = -16.0
    /// Highest peak a pad may reach after balancing.
    static let peakCeiling: Float = 0.9
    /// Never boost or cut a sample by more than this.
    static let maxAdjustDB = 18.0

    /// Target loudness for a pad, relative to the kick, in dB.
    public static func targetOffset(kit: DrumKit, pad: Int) -> Double {
        let name = kit.padNames[pad]
        switch name {
        case "Kick", "Cajón": return 0
        case "Snare", "Slap": return -1
        case "Clap": return -3
        case "Low Tom", "High Tom", "Tom", "Conga", "Bongo Low", "Bongo High": return -3
        case "Closed Hat": return -8
        case "Open Hat": return -7
        case "Shaker": return -9
        case "Tambourine": return -8
        case "Ride": return -8
        case "Crash": return -6
        case "Cowbell", "Woodblock": return -7
        case "Rim": return -6
        default: return -6
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var gains: [String: Float] = [:]

    /// The gain that brings one pad's one-shot to its place in the kit. Cached.
    public static func gain(kit: DrumKit, pad: Int, variant: Int, sampleRate: Double, raw: () -> [Float]) -> Float {
        let key = "\(kit.rawValue)/\(pad)/\(variant)@\(Int(sampleRate))"
        lock.lock()
        if let g = gains[key] { lock.unlock(); return g }
        lock.unlock()
        // The kit's kick sets the reference: wherever it actually lands (a
        // quiet kick can only be raised as far as its peak allows), the other
        // pads sit relative to it.
        let reference = pad == 0
            ? kickLoudness
            : landedLoudness(kit.rawSample(pad: 0, variant: 0, sampleRate: sampleRate), target: kickLoudness, sampleRate: sampleRate)
        let g = gain(for: raw(), target: reference + targetOffset(kit: kit, pad: pad), sampleRate: sampleRate)
        lock.lock()
        gains[key] = g
        lock.unlock()
        return g
    }

    static func gain(for samples: [Float], target: Double, sampleRate: Double) -> Float {
        let loud = loudness(samples, sampleRate: sampleRate)
        guard loud.isFinite else { return 1 }
        let adjust = min(max(target - loud, -maxAdjustDB), maxAdjustDB)
        var g = Float(pow(10, adjust / 20))
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if peak * g > peakCeiling { g = peakCeiling / max(peak, 1e-9) }
        return g
    }

    /// Loudness a sample ends up at when aimed at `target` (peak permitting).
    static func landedLoudness(_ samples: [Float], target: Double, sampleRate: Double) -> Double {
        let g = gain(for: samples, target: target, sampleRate: sampleRate)
        return loudness(samples, sampleRate: sampleRate) + 20 * log10(Double(max(g, 1e-9)))
    }

    /// Forgets cached gains (tests that swap the sample folder).
    static func resetCache() {
        lock.lock()
        gains = [:]
        lock.unlock()
    }

    /// K-weighted loudness of the loudest 150 ms, in dB (LUFS-style).
    public static func loudness(_ samples: [Float], sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return -.infinity }
        // BS.1770 K-weighting at 48 kHz: high shelf (+4 dB above ~1.5 kHz),
        // then a high-pass around 38 Hz. Other rates use the same filters,
        // close enough for balancing.
        var shelf = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                           a1: -1.69065929318241, a2: 0.73248077421585)
        var highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: -1.99004745483398, a2: 0.99007225036621)
        let window = max(1, Int(sampleRate * 0.15))
        var squares = [Double](repeating: 0, count: samples.count)
        for i in samples.indices {
            let y = highPass.process(shelf.process(Double(samples[i])))
            squares[i] = y * y
        }
        var sum = 0.0
        var best = 0.0
        for i in squares.indices {
            sum += squares[i]
            if i >= window { sum -= squares[i - window] }
            best = max(best, sum)
        }
        let mean = best / Double(min(window, samples.count))
        return mean > 0 ? -0.691 + 10 * log10(mean) : -.infinity
    }

    private struct Biquad {
        let b0, b1, b2, a1, a2: Double
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
            self.b0 = b0; self.b1 = b1; self.b2 = b2; self.a1 = a1; self.a2 = a2
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }
}
