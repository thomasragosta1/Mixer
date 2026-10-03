import Foundation

/// Downsampled peak arrays for fast waveform drawing (one peak per ~10 ms).
public enum PeakGenerator {
    public static let framesPerPeak = 480 // 10 ms at 48 kHz

    public static func peaks(of samples: [Float], framesPerPeak: Int = framesPerPeak) -> [Float] {
        var acc = PeakAccumulator(framesPerPeak: framesPerPeak)
        samples.withUnsafeBufferPointer { acc.append($0) }
        return acc.finish()
    }

    /// Streams a CAF file and returns its peaks.
    public static func peaks(ofFileAt url: URL, framesPerPeak: Int = framesPerPeak) throws -> [Float] {
        let reader = try CAFReader(url: url)
        var acc = PeakAccumulator(framesPerPeak: framesPerPeak)
        let chunk = framesPerPeak * 256
        var frame: Int64 = 0
        while frame < reader.frameCount {
            let n = Int(min(Int64(chunk), reader.frameCount - frame))
            let block = try reader.read(from: frame, count: n)
            block.withUnsafeBufferPointer { acc.append($0) }
            frame += Int64(n)
        }
        return acc.finish()
    }

    // MARK: Cache files (raw little-endian Float32)

    public static func write(_ peaks: [Float], to url: URL) throws {
        var data = Data(capacity: peaks.count * 4)
        for p in peaks {
            var le = p.bitPattern.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let count = data.count / 4
        var out = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            for i in 0..<count {
                let b = raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                out[i] = Float(bitPattern: UInt32(littleEndian: b))
            }
        }
        return out
    }
}

/// Incremental peak builder, used both for files and for the live waveform
/// while recording.
public struct PeakAccumulator {
    public let framesPerPeak: Int
    public private(set) var peaks: [Float] = []
    private var current: Float = 0
    private var count = 0

    public init(framesPerPeak: Int = PeakGenerator.framesPerPeak) {
        self.framesPerPeak = max(1, framesPerPeak)
    }

    public mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        for s in samples {
            let a = abs(s)
            if a > current { current = a }
            count += 1
            if count == framesPerPeak {
                peaks.append(min(current, 1))
                current = 0
                count = 0
            }
        }
    }

    /// The peak of the partially filled bucket, for live drawing.
    public var pending: Float? { count > 0 ? min(current, 1) : nil }

    public mutating func finish() -> [Float] {
        if count > 0 {
            peaks.append(min(current, 1))
            current = 0
            count = 0
        }
        return peaks
    }
}
