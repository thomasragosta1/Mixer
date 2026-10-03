import Foundation

/// Sample-by-sample processing stage of the Cleanup chain.
public protocol CleanupStage {
    /// Processes `samples` in place. State carries across calls.
    mutating func process(_ samples: inout [Float])
}

/// In-house de-esser: splits off the band above ~5 kHz and turns it down when
/// it dominates the signal (harsh "s" sounds). With full gain the bands sum
/// back to the input exactly, so quiet passages are untouched.
public struct DeEsser: CleanupStage {
    public var strength: Double
    private var splitter: Biquad
    private var highEnv: EnvelopeFollower
    private var fullEnv: EnvelopeFollower
    private var gainSmoother: Float = 1
    private let smoothCoeff: Float
    /// Maximum reduction of the sibilant band at full strength.
    static let maxReductionDB = 12.0
    /// Sibilance is detected when the high band is this share of the whole.
    static let ratioThreshold: Float = 0.35
    /// Ignore very quiet material (noise floor).
    static let levelFloor: Float = 0.003

    public init(strength: Double, sampleRate: Double = CAFFormat.defaultSampleRate) {
        self.strength = min(max(strength, 0), 1)
        splitter = .highPass(frequency: 5_000, sampleRate: sampleRate)
        highEnv = EnvelopeFollower(attack: 0.001, release: 0.04, sampleRate: sampleRate)
        fullEnv = EnvelopeFollower(attack: 0.001, release: 0.04, sampleRate: sampleRate)
        smoothCoeff = Float(exp(-1 / (0.002 * sampleRate)))
    }

    public mutating func process(_ samples: inout [Float]) {
        guard strength > 0 else { return }
        let minGain = Float(MacroCurves.dbToGain(-DeEsser.maxReductionDB * strength))
        for i in samples.indices {
            let x = samples[i]
            let high = splitter.process(x)
            let h = highEnv.process(high)
            let f = fullEnv.process(x)
            var target: Float = 1
            if f > DeEsser.levelFloor {
                let ratio = h / f
                if ratio > DeEsser.ratioThreshold {
                    // Scale the band so its share comes back toward the threshold.
                    target = max(minGain, DeEsser.ratioThreshold / ratio)
                }
            }
            gainSmoother = target + smoothCoeff * (gainSmoother - target)
            samples[i] = x - (1 - gainSmoother) * high
        }
    }
}

/// Simple de-reverb: a downward expander that pulls down decaying room tails
/// between phrases while leaving direct sound alone. It compares a fast
/// envelope with a slow "recent peak" envelope; when the signal has fallen
/// well below the recent peak, it is mostly reverb and gets attenuated.
public struct TailSuppressor: CleanupStage {
    public var strength: Double
    private var fast: EnvelopeFollower
    private var slow: EnvelopeFollower
    private var gain: Float = 1
    private let attackCoeff: Float
    private let releaseCoeff: Float
    static let maxReductionDB = 9.0
    /// Below this fraction of the recent peak, the expander starts working.
    static let knee: Float = 0.25

    public init(strength: Double, sampleRate: Double = CAFFormat.defaultSampleRate) {
        self.strength = min(max(strength, 0), 1)
        fast = EnvelopeFollower(attack: 0.002, release: 0.03, sampleRate: sampleRate)
        slow = EnvelopeFollower(attack: 0.002, release: 0.6, sampleRate: sampleRate)
        attackCoeff = Float(exp(-1 / (0.003 * sampleRate)))
        releaseCoeff = Float(exp(-1 / (0.08 * sampleRate)))
    }

    public mutating func process(_ samples: inout [Float]) {
        guard strength > 0 else { return }
        let floorGain = Float(MacroCurves.dbToGain(-TailSuppressor.maxReductionDB * strength))
        for i in samples.indices {
            let x = samples[i]
            let f = fast.process(x)
            let s = slow.process(x)
            var target: Float = 1
            if s > 1e-5 {
                let rel = f / s
                if rel < TailSuppressor.knee {
                    // Linear in the ratio: full reduction once the tail is 4x further down.
                    let depth = min(1, (TailSuppressor.knee - rel) / (TailSuppressor.knee * 0.75))
                    target = 1 - depth * (1 - floorGain)
                }
            }
            // Open quickly for new notes, close slowly to avoid pumping.
            let c = target > gain ? attackCoeff : releaseCoeff
            gain = target + c * (gain - target)
            samples[i] = x * gain
        }
    }
}
