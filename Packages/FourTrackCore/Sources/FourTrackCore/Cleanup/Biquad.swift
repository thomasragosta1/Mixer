import Foundation

/// RBJ-cookbook biquad, transposed direct form II. Used by the in-house
/// Cleanup stages; playback EQ uses AVAudioUnitEQ instead.
public struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    public static func highPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let c = cos(w0)
        let a0 = 1 + alpha
        var f = Biquad()
        f.b0 = Float((1 + c) / 2 / a0)
        f.b1 = Float(-(1 + c) / a0)
        f.b2 = Float((1 + c) / 2 / a0)
        f.a1 = Float(-2 * c / a0)
        f.a2 = Float((1 - alpha) / a0)
        return f
    }

    /// High shelf, `gainDB` above `frequency` (RBJ, shelf slope 1).
    public static func highShelf(frequency: Double, gainDB: Double, sampleRate: Double) -> Biquad {
        let A = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let c = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2)
        let sq = 2 * sqrt(A) * alpha
        let a0 = (A + 1) - (A - 1) * c + sq
        var f = Biquad()
        f.b0 = Float(A * ((A + 1) + (A - 1) * c + sq) / a0)
        f.b1 = Float(-2 * A * ((A - 1) + (A + 1) * c) / a0)
        f.b2 = Float(A * ((A + 1) + (A - 1) * c - sq) / a0)
        f.a1 = Float(2 * ((A - 1) - (A + 1) * c) / a0)
        f.a2 = Float(((A + 1) - (A - 1) * c - sq) / a0)
        return f
    }

    public static func lowPass(frequency: Double, q: Double = 0.7071, sampleRate: Double) -> Biquad {
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let c = cos(w0)
        let a0 = 1 + alpha
        var f = Biquad()
        f.b0 = Float((1 - c) / 2 / a0)
        f.b1 = Float((1 - c) / a0)
        f.b2 = Float((1 - c) / 2 / a0)
        f.a1 = Float(-2 * c / a0)
        f.a2 = Float((1 - alpha) / a0)
        return f
    }

    @inline(__always)
    public mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    public mutating func reset() {
        z1 = 0
        z2 = 0
    }
}

/// One-pole envelope follower with separate attack and release.
public struct EnvelopeFollower {
    let attackCoeff: Float
    let releaseCoeff: Float
    public private(set) var value: Float = 0

    public init(attack: Double, release: Double, sampleRate: Double) {
        attackCoeff = Float(exp(-1 / (max(attack, 1e-5) * sampleRate)))
        releaseCoeff = Float(exp(-1 / (max(release, 1e-5) * sampleRate)))
    }

    @inline(__always)
    public mutating func process(_ x: Float) -> Float {
        let a = abs(x)
        let c = a > value ? attackCoeff : releaseCoeff
        value = a + c * (value - a)
        return value
    }
}
