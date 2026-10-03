import Foundation
@testable import FourTrackCore

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("FourTrackTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
func writeCAF(_ samples: [Float], to url: URL, sampleRate: Double = 48_000) throws -> URL {
    let w = try CAFWriter(url: url, sampleRate: sampleRate)
    try w.write(samples)
    try w.finish()
    return url
}

func readCAF(_ url: URL) throws -> [Float] {
    try CAFReader(url: url).readAll()
}

/// Deterministic pseudo-random generator so DSP tests are repeatable.
struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    /// Uniform in -1...1.
    mutating func nextFloat() -> Float {
        Float(Double(next() >> 11) / Double(1 << 53)) * 2 - 1
    }
}

func sine(frequency: Double, seconds: Double, amplitude: Float = 0.5, sampleRate: Double = 48_000) -> [Float] {
    let n = Int(seconds * sampleRate)
    return (0..<n).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

func rms(_ x: ArraySlice<Float>) -> Float {
    guard !x.isEmpty else { return 0 }
    return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
}

func rms(_ x: [Float]) -> Float { rms(x[...]) }

/// Largest sample-to-sample jump, a crude click detector.
func maxStep(_ x: ArraySlice<Float>) -> Float {
    var m: Float = 0
    var prev: Float? = nil
    for v in x {
        if let p = prev { m = max(m, abs(v - p)) }
        prev = v
    }
    return m
}
