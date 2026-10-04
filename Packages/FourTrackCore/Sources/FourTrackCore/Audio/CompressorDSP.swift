import Foundation

/// In-house feed-forward compressor (Giannoulis, Massberg & Reiss, "Digital
/// Dynamic Range Compressor Design", JAES 2012): log-domain gain computer with
/// a soft knee, and a smooth branching peak detector on the gain reduction.
/// Stereo-linked, so the image never shifts. Allocation-free and lock-free,
/// so it is safe to run on the audio render thread.
public final class CompressorDSP {
    /// Written from the main thread, read once per render block.
    public var params: CompressorParams
    public private(set) var sampleRate: Double
    /// Smoothed gain reduction in dB (>= 0).
    private var reductionDB: Float = 0
    /// Latest block's maximum gain reduction, for metering.
    public private(set) var lastReductionDB: Float = 0

    public init(params: CompressorParams, sampleRate: Double = CAFFormat.defaultSampleRate) {
        self.params = params
        self.sampleRate = sampleRate
    }

    public func reset(sampleRate: Double? = nil) {
        if let sampleRate { self.sampleRate = sampleRate }
        reductionDB = 0
        lastReductionDB = 0
    }

    /// Static curve: output level in dB for an input level in dB (before makeup).
    public static func gainComputer(_ x: Float, threshold t: Float, ratio r: Float, knee w: Float) -> Float {
        let over = x - t
        if w > 0 && 2 * abs(over) <= w {
            let k = over + w / 2
            return x + (1 / r - 1) * k * k / (2 * w)
        }
        return over > 0 ? t + over / r : x
    }

    /// Processes up to two channels in place.
    public func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>?, frames: Int) {
        let p = params
        let ratio = Float(max(p.ratio, 1))
        let makeup = Float(p.makeupGainDB)
        guard ratio > 1.0001 else {
            // 1:1 is a pure gain stage.
            let g = powf(10, makeup / 20)
            if g != 1 {
                for i in 0..<frames { left[i] *= g; right?[i] *= g }
            }
            reductionDB = 0
            lastReductionDB = 0
            return
        }
        let threshold = Float(p.thresholdDB)
        let knee = Float(max(p.kneeDB, 0))
        let sr = Float(sampleRate)
        let aA = expf(-1 / (Float(max(p.attackSeconds, 1e-5)) * sr))
        let aR = expf(-1 / (Float(max(p.releaseSeconds, 1e-4)) * sr))
        var y = reductionDB
        var peakGR: Float = 0
        for i in 0..<frames {
            let l = left[i]
            let r = right?[i] ?? l
            let level = max(abs(l), abs(r))
            let xDB = 20 * log10f(max(level, 1e-6))
            let target = xDB - Self.gainComputer(xDB, threshold: threshold, ratio: ratio, knee: knee)
            y = target > y ? aA * y + (1 - aA) * target : aR * y + (1 - aR) * target
            peakGR = max(peakGR, y)
            let g = powf(10, (makeup - y) / 20)
            left[i] = l * g
            right?[i] = r * g
        }
        reductionDB = y.isFinite ? y : 0
        lastReductionDB = peakGR
    }

    /// Convenience for offline use and tests.
    public func process(_ samples: inout [Float]) {
        let n = samples.count
        samples.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            process(base, nil, frames: n)
        }
    }
}
