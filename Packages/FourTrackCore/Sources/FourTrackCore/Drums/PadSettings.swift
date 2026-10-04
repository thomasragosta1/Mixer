import Foundation

/// Per-pad sound adjustments on a drum track (press and hold a pad). Stored as
/// slider values, like the mixer, so tuning the curves later improves old projects.
public struct PadSettings: Codable, Equatable, Sendable {
    /// 0...1, unity at 0.75 (same curve as the track volume fader).
    public var volume: Double
    /// -1...1 → -12...+12 semitones.
    public var tune: Double
    /// 0...1: 1 is the natural ring, lower damps it.
    public var decay: Double
    /// -1...1: darker ... brighter.
    public var tone: Double

    public init(volume: Double = MacroCurves.volumeUnitySlider, tune: Double = 0, decay: Double = 1, tone: Double = 0) {
        self.volume = volume
        self.tune = tune
        self.decay = decay
        self.tone = tone
    }

    public static let `default` = PadSettings()

    public var isDefault: Bool { self == .default }

    public static let tuneRangeSemitones: Double = 12
    public var semitones: Double { (tune * PadSettings.tuneRangeSemitones).rounded() }

    enum CodingKeys: String, CodingKey { case volume, tune, decay, tone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? volume
        tune = try c.decodeIfPresent(Double.self, forKey: .tune) ?? 0
        decay = try c.decodeIfPresent(Double.self, forKey: .decay) ?? 1
        tone = try c.decodeIfPresent(Double.self, forKey: .tone) ?? 0
    }
}

/// Applies `PadSettings` to a one-shot. Pure and offline; the live pads and
/// the track render use the same function, so they always match.
public enum PadProcessor {
    public static func apply(_ samples: [Float], _ s: PadSettings, sampleRate: Double = CAFFormat.defaultSampleRate) -> [Float] {
        guard !s.isDefault, !samples.isEmpty else { return samples }
        var out = samples

        // Tune: play the sample faster or slower (pitch and length move together, like a sampler).
        let semis = s.semitones
        if semis != 0 {
            let ratio = pow(2, semis / 12)
            let n = max(2, Int(Double(out.count) / ratio))
            out = (0..<n).map { i in
                let pos = Double(i) * ratio
                let j = min(Int(pos), samples.count - 2)
                let f = Float(pos - Double(j))
                return samples[j] * (1 - f) + samples[j + 1] * f
            }
        }

        // Tone: a high shelf at 3 kHz, up to +9 dB brighter or -15 dB darker.
        if abs(s.tone) > 0.005 {
            let gain = s.tone > 0 ? s.tone * 9 : s.tone * 15
            var shelf = Biquad.highShelf(frequency: 3_000, gainDB: gain, sampleRate: sampleRate)
            for i in out.indices { out[i] = shelf.process(out[i]) }
        }

        // Decay: below 1, an exponential damping after a short hold so the attack stays intact.
        if s.decay < 0.995 {
            let hold = 0.02 * sampleRate
            // decay 0 → 25 ms time constant; approaching 1 → 2 s (effectively natural).
            let tau = 0.025 * pow(80, max(0, s.decay)) * sampleRate
            for i in out.indices where Double(i) > hold {
                out[i] *= Float(exp(-(Double(i) - hold) / tau))
            }
            // Drop the now-silent tail.
            var end = out.count
            while end > 1 && abs(out[end - 1]) < 0.0003 { end -= 1 }
            out.removeSubrange(end...)
        }

        // Volume.
        let g = Float(MacroCurves.volumeGain(s.volume))
        if g != 1 { for i in out.indices { out[i] *= g } }

        // Short fade so a shortened or retuned sample never ends with a click.
        let fade = min(out.count, Int(0.004 * sampleRate))
        for k in 0..<fade { out[out.count - 1 - k] *= Float(k) / Float(max(fade, 1)) }
        return out
    }
}
