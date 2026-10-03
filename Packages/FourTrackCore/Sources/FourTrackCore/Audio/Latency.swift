import Foundation

/// Round-trip latency handling. Recorded audio arrives late relative to what
/// the performer heard; the recorder shifts it earlier by this amount before
/// splicing.
public enum LatencyModel {
    /// Spec formula: input + output presentation latency + two IO buffers.
    public static func estimate(inputLatency: Double, outputLatency: Double, ioBufferDuration: Double) -> Double {
        max(0, inputLatency) + max(0, outputLatency) + 2 * max(0, ioBufferDuration)
    }
}

/// Stored per audio route: a calibrated measurement (if any) plus the manual
/// Developer Mode adjustment.
public struct LatencySettings: Codable, Equatable, Sendable {
    /// Seconds measured by the calibration helper, per route.
    public var measured: [AudioRouteKind: Double]
    /// Manual offset in milliseconds added on top, per route.
    public var manualOffsetMs: [AudioRouteKind: Double]
    /// Whether the one-time Bluetooth tip has been shown.
    public var bluetoothTipShown: Bool

    public init(measured: [AudioRouteKind: Double] = [:], manualOffsetMs: [AudioRouteKind: Double] = [:], bluetoothTipShown: Bool = false) {
        self.measured = measured
        self.manualOffsetMs = manualOffsetMs
        self.bluetoothTipShown = bluetoothTipShown
    }

    public static let manualRangeMs: ClosedRange<Double> = -100...300

    /// Compensation in seconds for `route`: calibrated value when available,
    /// otherwise the system estimate, plus the manual offset.
    public func compensation(for route: AudioRouteKind, estimate: Double) -> Double {
        let base = measured[route] ?? estimate
        return max(0, base + (manualOffsetMs[route] ?? 0) / 1000)
    }
}

/// Signal analysis for the "calibrate" helper: play clicks, record them back,
/// find how late they arrive.
public enum LatencyCalibration {
    /// Returns the delay in frames between each click's scheduled timeline
    /// position and its arrival in `recorded`, using the median over clicks for
    /// robustness. nil if no click is found clearly above the noise floor.
    public static func measureDelay(
        recorded: [Float],
        clickFrames: [Int],
        template: [Float],
        maxDelayFrames: Int
    ) -> Int? {
        guard !template.isEmpty else { return nil }
        let tEnergy = template.reduce(0) { $0 + $1 * $1 }
        guard tEnergy > 0 else { return nil }
        var delays: [Int] = []
        for click in clickFrames {
            var best = -Float.greatestFiniteMagnitude
            var bestLag = -1
            var sumScores: Float = 0
            var n = 0
            for lag in 0...maxDelayFrames {
                let start = click + lag
                if start < 0 || start + template.count > recorded.count { break }
                var dot: Float = 0
                var energy: Float = 0
                for j in 0..<template.count {
                    let r = recorded[start + j]
                    dot += r * template[j]
                    energy += r * r
                }
                // Normalized cross-correlation, insensitive to level.
                let score = energy > 0 ? dot / (energy.squareRoot() * tEnergy.squareRoot()) : 0
                sumScores += abs(score)
                n += 1
                if score > best {
                    best = score
                    bestLag = lag
                }
            }
            let mean = n > 0 ? sumScores / Float(n) : 0
            if bestLag >= 0, best > 0.5, best > mean * 3 {
                delays.append(bestLag)
            }
        }
        guard delays.count >= max(1, clickFrames.count / 2) else { return nil }
        delays.sort()
        return delays[delays.count / 2]
    }
}

/// Click synthesis and beat timing for the metronome and count-in.
public enum ClickTrack {
    /// A short decaying sine burst. Accented clicks are higher and louder.
    public static func click(sampleRate: Double = CAFFormat.defaultSampleRate, accent: Bool) -> [Float] {
        let duration = 0.03
        let freq = accent ? 1_760.0 : 1_175.0
        let amp: Float = accent ? 0.9 : 0.6
        let n = Int(duration * sampleRate)
        return (0..<n).map { i in
            let t = Double(i) / sampleRate
            let env = exp(-t * 160)
            // 1 ms linear attack avoids a click on the click.
            let attack = min(1, t / 0.001)
            return amp * Float(sin(2 * .pi * freq * t) * env * attack)
        }
    }

    public static func framesPerBeat(bpm: Double, sampleRate: Double = CAFFormat.defaultSampleRate) -> Double {
        sampleRate * 60 / max(1, bpm)
    }

    /// Timeline frames of beats in [startFrame, endFrame), on a grid anchored at
    /// frame 0, with whether each is the first beat of its bar.
    public static func beats(from startFrame: Int64, to endFrame: Int64, bpm: Double, beatsPerBar: Int, sampleRate: Double = CAFFormat.defaultSampleRate) -> [(frame: Int64, accent: Bool)] {
        let fpb = framesPerBeat(bpm: bpm, sampleRate: sampleRate)
        guard endFrame > startFrame, fpb > 0 else { return [] }
        // Negative frames are allowed so a count-in can run before timeline 0.
        let bar = Int64(max(1, beatsPerBar))
        var beatIndex = Int64((Double(startFrame) / fpb).rounded(.up))
        var out: [(Int64, Bool)] = []
        while true {
            let f = Int64((Double(beatIndex) * fpb).rounded())
            if f >= endFrame { break }
            if f >= startFrame {
                out.append((f, ((beatIndex % bar) + bar) % bar == 0))
            }
            beatIndex += 1
        }
        return out
    }

    /// Length of a count-in in frames.
    public static func countInFrames(bars: Int, bpm: Double, beatsPerBar: Int, sampleRate: Double = CAFFormat.defaultSampleRate) -> Int64 {
        Int64((Double(max(0, bars) * max(1, beatsPerBar)) * framesPerBeat(bpm: bpm, sampleRate: sampleRate)).rounded())
    }
}
