import Foundation

/// The three built-in drum kits, each with its own character:
/// - Studio: a real acoustic kit, multi-sampled (Big Rusty Drums by Karoryfer, CC0)
/// - 808: classic analog drum machine, synthesized (boomy pitched kick, clap, cowbell)
/// - Hand Percussion: real cajón, bongos, conga, shaker, tambourine and woodblock
///   (Versilian Community Sample Library, CC0)
/// Sampled kits carry two recorded takes per pad that alternate on repeated hits,
/// so fast patterns don't sound machine-gunned.
public enum DrumKit: String, Codable, CaseIterable, Sendable, Identifiable {
    case studio
    case eightOhEight
    case handPercussion

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .studio: return "Studio"
        case .eightOhEight: return "808"
        case .handPercussion: return "Hand Percussion"
        }
    }

    public static let padCount = 8

    /// Pad names, in pad order (top-left to bottom-right on a 4 x 2 grid).
    public var padNames: [String] {
        switch self {
        case .studio:
            return ["Kick", "Snare", "Closed Hat", "Open Hat", "Low Tom", "High Tom", "Ride", "Crash"]
        case .eightOhEight:
            return ["Kick", "Snare", "Clap", "Closed Hat", "Open Hat", "Cowbell", "Rim", "Tom"]
        case .handPercussion:
            return ["Cajón", "Slap", "Bongo Low", "Bongo High", "Conga", "Shaker", "Tambourine", "Woodblock"]
        }
    }

    /// What a pad is, so the UI can colour pads by family.
    public enum PadFamily: Sendable { case kick, snare, hat, tom, cymbal, accent }

    public func family(of pad: Int) -> PadFamily {
        switch self {
        case .studio: return [.kick, .snare, .hat, .hat, .tom, .tom, .cymbal, .cymbal][pad]
        case .eightOhEight: return [.kick, .snare, .snare, .hat, .hat, .accent, .accent, .tom][pad]
        case .handPercussion: return [.kick, .snare, .tom, .tom, .tom, .hat, .hat, .accent][pad]
        }
    }

    /// Where each sound sits on the 4 x 2 pad grid, rows top to bottom.
    /// Same idea in every kit, like a finger-drumming pad: the groove (kick,
    /// snare, hats) is the bottom row under the thumbs, kick bottom-left;
    /// toms and cymbals/colour sounds sit above, low on the left, high on the right.
    public var padLayout: [[Int]] {
        switch self {
        // Bottom: Kick, Snare, Closed Hat, Open Hat. Top: High Tom, Low Tom, Ride, Crash.
        case .studio: return [[5, 4, 6, 7], [0, 1, 2, 3]]
        // Bottom: Kick, Snare, Closed Hat, Open Hat. Top: Tom, Rim, Clap, Cowbell.
        case .eightOhEight: return [[7, 6, 2, 5], [0, 1, 3, 4]]
        // Bottom: Cajón, Slap, Shaker, Tambourine. Top: Conga, Bongo Low, Bongo High, Woodblock.
        case .handPercussion: return [[4, 2, 3, 7], [0, 1, 5, 6]]
        }
    }

    /// Number of alternate takes per pad.
    public var variantCount: Int {
        switch self {
        case .studio, .handPercussion: return 2
        case .eightOhEight: return 1
        }
    }

    /// Folder under `Resources/Drums` for sampled kits.
    var sampleFolder: String? {
        switch self {
        case .studio: return "studio"
        case .handPercussion: return "hand"
        case .eightOhEight: return nil
        }
    }

    /// One-shot for a pad at full velocity. `variant` picks the recorded take
    /// (wrapped to `variantCount`). Falls back to synthesis if a sample is missing.
    public func sample(pad: Int, variant: Int = 0, sampleRate: Double = CAFFormat.defaultSampleRate) -> [Float] {
        if sampleFolder != nil, let s = DrumSamples.load(kit: self, pad: pad, variant: variant % max(variantCount, 1), sampleRate: sampleRate) {
            return s
        }
        return DrumSynth.render(kit: self, pad: pad, sampleRate: sampleRate)
    }
}

/// Loads (and caches) the drum samples. They ship inside the app (a "Drums"
/// folder with `studio/` and `hand/`), not as a package resource bundle, so a
/// missing file can never crash: the kit falls back to synthesis instead.
public enum DrumSamples {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [Float]] = [:]
    nonisolated(unsafe) private static var _directory: URL?

    /// Folder holding `studio/` and `hand/`. Defaults to `Drums` in the main bundle.
    public static var directory: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _directory ?? Bundle.main.url(forResource: "Drums", withExtension: nil)
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _directory = newValue
            cache = [:]
        }
    }

    static func load(kit: DrumKit, pad: Int, variant: Int, sampleRate: Double) -> [Float]? {
        guard let folder = kit.sampleFolder else { return nil }
        let key = "\(folder)/\(pad)_\(variant + 1)@\(Int(sampleRate))"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        guard let dir = directory else { return nil }
        let url = dir.appendingPathComponent(folder).appendingPathComponent("\(pad)_\(variant + 1).caf")
        guard FileManager.default.fileExists(atPath: url.path),
              let reader = try? CAFReader(url: url),
              var samples = try? reader.readAll(), !samples.isEmpty else { return nil }
        if abs(reader.sampleRate - sampleRate) > 0.5 {
            samples = resample(samples, from: reader.sampleRate, to: sampleRate)
        }
        lock.lock()
        cache[key] = samples
        lock.unlock()
        return samples
    }

    /// Linear-interpolation resampler; only used for non-48 kHz renders.
    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        let n = Int((Double(x.count) * to / from).rounded())
        guard n > 1, x.count > 1 else { return x }
        let step = from / to
        return (0..<n).map { i in
            let pos = Double(i) * step
            let j = min(Int(pos), x.count - 2)
            let f = Float(pos - Double(j))
            return x[j] * (1 - f) + x[j + 1] * f
        }
    }
}

/// One recorded pad hit on a drum track.
public struct DrumHit: Codable, Equatable, Sendable {
    /// Timeline position in seconds.
    public var time: Double
    public var pad: Int
    /// 0...1.
    public var velocity: Float

    public init(time: Double, pad: Int, velocity: Float = 0.9) {
        self.time = time
        self.pad = pad
        self.velocity = velocity
    }
}

/// Turns a list of hits into a track's audio.
public enum DrumRenderer {
    /// Replaces the hits in [start, end) with `newHits` (tape-style overwrite)
    /// and returns the merged, time-sorted list.
    public static func overwrite(_ existing: [DrumHit], from start: Double, to end: Double, with newHits: [DrumHit]) -> [DrumHit] {
        let kept = existing.filter { $0.time < start || $0.time >= end }
        return (kept + newHits.filter { $0.time >= 0 }).sorted { $0.time < $1.time }
    }

    /// Mixes all hits into one mono buffer. Overlapping hits sum, then a soft
    /// clipper keeps dense patterns from clipping. Empty for no hits.
    public static func render(_ hits: [DrumHit], kit: DrumKit, sampleRate: Double = CAFFormat.defaultSampleRate) -> [Float] {
        guard !hits.isEmpty else { return [] }
        var cache: [Int: [Float]] = [:]
        func sample(_ pad: Int, _ variant: Int) -> [Float] {
            let key = pad * 16 + variant
            if let s = cache[key] { return s }
            let s = kit.sample(pad: pad, variant: variant, sampleRate: sampleRate)
            cache[key] = s
            return s
        }
        // Alternate takes per pad in time order, like the live pad does.
        let ordered = hits.sorted { $0.time < $1.time }
        var counters: [Int: Int] = [:]
        let variants: [Int] = ordered.map { hit in
            let v = counters[hit.pad, default: 0]
            counters[hit.pad] = v + 1
            return v % max(kit.variantCount, 1)
        }
        var length = 0
        for (hit, v) in zip(ordered, variants) {
            let start = Int((max(0, hit.time) * sampleRate).rounded())
            length = max(length, start + sample(hit.pad, v).count)
        }
        var out = [Float](repeating: 0, count: length)
        for (hit, v) in zip(ordered, variants) {
            let start = Int((max(0, hit.time) * sampleRate).rounded())
            let s = sample(hit.pad, v)
            let v = min(max(hit.velocity, 0), 1)
            for i in 0..<s.count {
                out[start + i] += s[i] * v
            }
        }
        // Soft clip only above about -3 dBFS so normal material is untouched.
        for i in 0..<out.count {
            let x = out[i]
            if abs(x) > 0.7 {
                let sign: Float = x < 0 ? -1 : 1
                out[i] = sign * (0.7 + 0.3 * tanh((abs(x) - 0.7) / 0.3))
            }
        }
        return out
    }

    /// Renders and writes a drum track atomically; returns the frame count.
    @discardableResult
    public static func write(_ hits: [DrumHit], kit: DrumKit, to url: URL, sampleRate: Double = CAFFormat.defaultSampleRate) throws -> Int {
        let samples = render(hits, kit: kit, sampleRate: sampleRate)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).drums-\(UUID().uuidString)")
        let writer = try CAFWriter(url: temp, sampleRate: sampleRate)
        do {
            try writer.write(samples)
            try writer.finish()
            try AtomicFile.replace(url, with: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        return samples.count
    }
}

// MARK: - Synthesis

enum DrumSynth {
    static func render(kit: DrumKit, pad: Int, sampleRate sr: Double) -> [Float] {
        var noise = Noise(seed: UInt64(pad * 7919 + kit.hashSeed))
        switch kit {
        case .studio:
            switch pad {
            case 0: return kick(sr, start: 140, end: 52, pitchDecay: 0.035, decay: 0.32, click: 0.35, noise: &noise)
            case 1: return snare(sr, tone: 185, toneDecay: 0.08, noiseDecay: 0.18, noiseLevel: 0.75, bright: 2_500, noise: &noise)
            case 2: return hat(sr, decay: 0.045, hp: 7_000, metallic: false, noise: &noise)
            case 3: return hat(sr, decay: 0.38, hp: 6_500, metallic: false, noise: &noise)
            case 4: return tom(sr, start: 150, end: 95, decay: 0.42, noise: &noise)
            case 5: return tom(sr, start: 240, end: 165, decay: 0.32, noise: &noise)
            case 6: return ride(sr, noise: &noise)
            default: return crash(sr, noise: &noise)
            }
        case .eightOhEight:
            switch pad {
            case 0: return kick(sr, start: 95, end: 44, pitchDecay: 0.06, decay: 0.95, click: 0.08, noise: &noise)
            case 1: return snare(sr, tone: 238, toneDecay: 0.06, noiseDecay: 0.13, noiseLevel: 0.55, bright: 4_500, secondTone: 476, noise: &noise)
            case 2: return clap(sr, noise: &noise)
            case 3: return hat(sr, decay: 0.05, hp: 7_500, metallic: true, noise: &noise)
            case 4: return hat(sr, decay: 0.32, hp: 7_000, metallic: true, noise: &noise)
            case 5: return cowbell(sr)
            case 6: return rim(sr, noise: &noise)
            default: return tom(sr, start: 160, end: 110, decay: 0.55, noise: &noise, noiseLevel: 0)
            }
        case .handPercussion:
            switch pad {
            case 0: return cajonBass(sr, noise: &noise)
            case 1: return cajonSlap(sr, noise: &noise)
            case 2: return bongo(sr, freq: 220, decay: 0.22, noise: &noise)
            case 3: return bongo(sr, freq: 340, decay: 0.16, noise: &noise)
            case 4: return bongo(sr, freq: 175, decay: 0.38, noise: &noise)
            case 5: return shaker(sr, noise: &noise)
            case 6: return tambourine(sr, noise: &noise)
            default: return woodblock(sr)
            }
        }
    }

    // MARK: Voices

    static func kick(_ sr: Double, start: Double, end: Double, pitchDecay: Double, decay: Double, click: Float, noise: inout Noise) -> [Float] {
        let n = Int(sr * (decay * 4))
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = end + (start - end) * exp(-t / pitchDecay)
            phase += 2 * .pi * f / sr
            let amp = exp(-t / decay)
            var s = Float(sin(phase) * amp)
            if t < 0.004 { s += click * noise.next() * Float(1 - t / 0.004) }
            out[i] = s * 0.95
        }
        return finish(out, sr)
    }

    static func snare(_ sr: Double, tone: Double, toneDecay: Double, noiseDecay: Double, noiseLevel: Float, bright: Double, secondTone: Double? = nil, noise: inout Noise) -> [Float] {
        let n = Int(sr * noiseDecay * 5)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: bright, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            var body = sin(2 * .pi * tone * t) * exp(-t / toneDecay)
            if let secondTone { body += 0.5 * sin(2 * .pi * secondTone * t) * exp(-t / (toneDecay * 0.7)) }
            let wires = hp.process(noise.next()) * noiseLevel * Float(exp(-t / noiseDecay))
            out[i] = Float(body) * 0.6 + wires
        }
        return finish(out, sr)
    }

    static func hat(_ sr: Double, decay: Double, hp cutoff: Double, metallic: Bool, noise: inout Noise) -> [Float] {
        let n = Int(sr * decay * 5)
        var out = [Float](repeating: 0, count: n)
        var hp1 = Biquad.highPass(frequency: cutoff, sampleRate: sr)
        var hp2 = Biquad.highPass(frequency: cutoff, sampleRate: sr)
        // The 808's six detuned square oscillators.
        let freqs = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
        for i in 0..<n {
            let t = Double(i) / sr
            var src: Float
            if metallic {
                var sum = 0.0
                for f in freqs { sum += sin(2 * .pi * f * 1.6 * t) > 0 ? 1 : -1 }
                src = Float(sum / 6) * 0.7 + noise.next() * 0.3
            } else {
                src = noise.next()
            }
            out[i] = hp2.process(hp1.process(src)) * Float(exp(-t / decay)) * 0.8
        }
        return finish(out, sr)
    }

    static func tom(_ sr: Double, start: Double, end: Double, decay: Double, noise: inout Noise, noiseLevel: Float = 0.15) -> [Float] {
        let n = Int(sr * decay * 4)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var lp = Biquad.lowPass(frequency: 3_000, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let f = end + (start - end) * exp(-t / 0.08)
            phase += 2 * .pi * f / sr
            let skin = sin(phase) * exp(-t / decay)
            let hit = lp.process(noise.next()) * noiseLevel * Float(exp(-t / 0.02))
            out[i] = Float(skin) * 0.85 + hit
        }
        return finish(out, sr)
    }

    static func ride(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 1.6)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: 5_000, sampleRate: sr)
        let partials: [(Double, Double)] = [(3_120, 0.5), (4_410, 0.35), (5_870, 0.25), (7_230, 0.2)]
        for i in 0..<n {
            let t = Double(i) / sr
            var bell = 0.0
            for (f, a) in partials { bell += a * sin(2 * .pi * f * t) }
            let wash = hp.process(noise.next()) * 0.4
            out[i] = (Float(bell * 0.35) + wash) * Float(exp(-t / 0.45))
        }
        return finish(out, sr)
    }

    static func crash(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 2.4)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: 3_500, sampleRate: sr)
        var lp = Biquad.lowPass(frequency: 12_000, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let attack = min(1, t / 0.003)
            out[i] = lp.process(hp.process(noise.next())) * Float(attack * exp(-t / 0.7)) * 0.9
        }
        return finish(out, sr)
    }

    static func clap(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 0.5)
        var out = [Float](repeating: 0, count: n)
        var bp1 = Biquad.highPass(frequency: 900, sampleRate: sr)
        var bp2 = Biquad.lowPass(frequency: 2_800, sampleRate: sr)
        // Several hands slightly apart, then the room.
        let bursts = [0.0, 0.011, 0.022, 0.031]
        for i in 0..<n {
            let t = Double(i) / sr
            var env = 0.0
            for b in bursts where t >= b { env = max(env, exp(-(t - b) / 0.007)) }
            env = max(env, t >= 0.031 ? 0.55 * exp(-(t - 0.031) / 0.12) : 0)
            out[i] = bp2.process(bp1.process(noise.next())) * Float(env) * 1.4
        }
        return finish(out, sr)
    }

    static func cowbell(_ sr: Double) -> [Float] {
        let n = Int(sr * 0.6)
        var out = [Float](repeating: 0, count: n)
        var bp = Biquad.lowPass(frequency: 4_000, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let sq1: Double = sin(2 * .pi * 540 * t) > 0 ? 1 : -1
            let sq2: Double = sin(2 * .pi * 800 * t) > 0 ? 1 : -1
            let env = 0.6 * exp(-t / 0.03) + 0.4 * exp(-t / 0.18)
            out[i] = bp.process(Float((sq1 + sq2) * 0.25 * env))
        }
        return finish(out, sr)
    }

    static func rim(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 0.12)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: 1_500, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let tone = sin(2 * .pi * 1_700 * t) * exp(-t / 0.012) + 0.6 * sin(2 * .pi * 460 * t) * exp(-t / 0.02)
            out[i] = Float(tone) * 0.7 + hp.process(noise.next()) * 0.3 * Float(exp(-t / 0.006))
        }
        return finish(out, sr)
    }

    static func cajonBass(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 0.6)
        var out = [Float](repeating: 0, count: n)
        var lp = Biquad.lowPass(frequency: 600, sampleRate: sr)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let f = 80 + 50 * exp(-t / 0.02)
            phase += 2 * .pi * f / sr
            let box = sin(phase) * exp(-t / 0.14)
            let palm = lp.process(noise.next()) * Float(exp(-t / 0.03)) * 0.6
            out[i] = Float(box) * 0.9 + palm
        }
        return finish(out, sr)
    }

    static func cajonSlap(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 0.35)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: 1_800, sampleRate: sr)
        var lp = Biquad.lowPass(frequency: 7_000, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            let wood = sin(2 * .pi * 330 * t) * exp(-t / 0.05) * 0.4
            let snares = lp.process(hp.process(noise.next())) * Float(exp(-t / 0.09))
            out[i] = Float(wood) + snares * 0.8
        }
        return finish(out, sr)
    }

    static func bongo(_ sr: Double, freq: Double, decay: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * decay * 4)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var hp = Biquad.highPass(frequency: 2_000, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            // A short upward pitch blip from the hand, then the tuned skin.
            let f = freq * (1 + 0.25 * exp(-t / 0.008))
            phase += 2 * .pi * f / sr
            let skin = sin(phase) * exp(-t / decay) + 0.25 * sin(phase * 2.3) * exp(-t / (decay * 0.4))
            let finger = hp.process(noise.next()) * Float(exp(-t / 0.004)) * 0.4
            out[i] = Float(skin) * 0.8 + finger
        }
        return finish(out, sr)
    }

    static func shaker(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 0.22)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: 5_500, sampleRate: sr)
        for i in 0..<n {
            let t = Double(i) / sr
            // Beads swell then settle.
            let env = (t / 0.03) * exp(1 - t / 0.03)
            out[i] = hp.process(noise.next()) * Float(env) * 0.75
        }
        return finish(out, sr)
    }

    static func tambourine(_ sr: Double, noise: inout Noise) -> [Float] {
        let n = Int(sr * 0.7)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad.highPass(frequency: 6_000, sampleRate: sr)
        let jingles = [6_100.0, 7_400.0, 8_900.0, 10_300.0]
        for i in 0..<n {
            let t = Double(i) / sr
            var ring = 0.0
            for (k, f) in jingles.enumerated() { ring += sin(2 * .pi * f * t + Double(k)) }
            let env = exp(-t / 0.16)
            out[i] = (hp.process(noise.next()) * 0.6 + Float(ring * 0.08)) * Float(env)
        }
        return finish(out, sr)
    }

    static func woodblock(_ sr: Double) -> [Float] {
        let n = Int(sr * 0.2)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            let tone = sin(2 * .pi * 1_180 * t) * exp(-t / 0.035) + 0.3 * sin(2 * .pi * 2_830 * t) * exp(-t / 0.015)
            out[i] = Float(tone) * 0.8
        }
        return finish(out, sr)
    }

    /// Trims trailing near-silence, adds a tiny fade, and normalizes to -1 dBFS.
    static func finish(_ samples: [Float], _ sr: Double) -> [Float] {
        var end = samples.count
        while end > 0 && abs(samples[end - 1]) < 0.0005 { end -= 1 }
        var out = Array(samples[0..<end])
        let fade = min(out.count, Int(sr * 0.005))
        for i in 0..<fade {
            out[out.count - 1 - i] *= Float(i) / Float(max(fade, 1))
        }
        let peak = out.map { abs($0) }.max() ?? 0
        if peak > 0 {
            let g = 0.89 / peak
            for i in out.indices { out[i] *= g }
        }
        return out
    }
}

/// Deterministic white noise, so every hit of a pad sounds identical and
/// renders are repeatable.
struct Noise {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Double(state >> 11) / Double(1 << 53)) * 2 - 1
    }
}

extension DrumKit {
    var hashSeed: Int {
        switch self {
        case .studio: return 1
        case .eightOhEight: return 2
        case .handPercussion: return 3
        }
    }
}
