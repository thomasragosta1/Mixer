import Foundation
import CRNNoise

/// A denoiser that works on fixed-size frames of 48 kHz mono audio.
public protocol CleanupProcessor {
    /// Frames per `process` call.
    var frameSize: Int { get }
    /// Output delay in samples, removed by the pipeline so the cleaned file
    /// lines up with the original for blending.
    var latency: Int { get }
    /// Denoises exactly `frameSize` samples (range -1...1).
    func process(_ frame: [Float]) -> [Float]
}

/// RNNoise (BSD-3-Clause, Xiph.Org / Mozilla), vendored at v0.1.1 with its
/// bundled model. Small and fast enough to run well faster than real time.
public final class RNNoiseProcessor: CleanupProcessor {
    private let state: OpaquePointer
    public let frameSize: Int
    /// RNNoise's overlap-add synthesis delays output by one frame.
    public let latency: Int
    static let scale: Float = 32_768

    public init() {
        state = rnnoise_create(nil)
        frameSize = Int(rnnoise_get_frame_size())
        latency = frameSize
    }

    deinit {
        rnnoise_destroy(state)
    }

    public func process(_ frame: [Float]) -> [Float] {
        precondition(frame.count == frameSize)
        // RNNoise expects 16-bit-scaled floats.
        let input = frame.map { $0 * RNNoiseProcessor.scale }
        var output = [Float](repeating: 0, count: frameSize)
        input.withUnsafeBufferPointer { inp in
            output.withUnsafeMutableBufferPointer { out in
                _ = rnnoise_process_frame(state, out.baseAddress, inp.baseAddress)
            }
        }
        let inv = 1 / RNNoiseProcessor.scale
        return output.map { $0 * inv }
    }
}

/// The offline "polish" pass: denoise, then de-ess and suppress room tails.
/// Renders a full-strength copy of a take; the Cleanup slider blends it with
/// the original at playback, so slider moves are instant and non-destructive.
public final class CleanupPipeline {
    public struct Options: Sendable {
        public var denoise: Bool = true
        public var deEssStrength: Double = 1
        public var deReverbStrength: Double = 1
        /// Keep this much of the original under the denoised signal, so the
        /// "full" render never sounds over-processed.
        public var denoiseFloorMix: Float = 0.05
        public init() {}
    }

    public enum Failure: Error { case cancelled }

    let options: Options
    let makeProcessor: () -> CleanupProcessor

    public init(options: Options = Options(), makeProcessor: @escaping () -> CleanupProcessor = { RNNoiseProcessor() }) {
        self.options = options
        self.makeProcessor = makeProcessor
    }

    /// Processes `input` into `output` (written atomically). Output has the same
    /// length as input and is time-aligned with it.
    /// - Parameters:
    ///   - progress: called with 0...1 from the processing thread.
    ///   - isCancelled: polled between chunks.
    public func render(input: URL, output: URL, progress: ((Double) -> Void)? = nil, isCancelled: (() -> Bool)? = nil) throws {
        let reader = try CAFReader(url: input)
        let sampleRate = reader.sampleRate
        let total = reader.frameCount
        let processor = makeProcessor()
        let frameSize = processor.frameSize
        let latency = options.denoise ? processor.latency : 0
        var deEsser = DeEsser(strength: options.deEssStrength, sampleRate: sampleRate)
        var tails = TailSuppressor(strength: options.deReverbStrength, sampleRate: sampleRate)

        let temp = output.deletingLastPathComponent()
            .appendingPathComponent(".\(output.lastPathComponent).cleanup-\(UUID().uuidString)")
        let writer = try CAFWriter(url: temp, sampleRate: sampleRate)
        do {
            let chunkFrames = frameSize * 100
            var readPos: Int64 = 0
            var toSkip = latency // processor delay to drop from the start
            var written: Int64 = 0
            // Delay line for the dry signal so the floor mix stays aligned.
            var dryDelay = [Float](repeating: 0, count: latency)
            // Read past the end by `latency` frames to flush the processor.
            let readEnd = total + Int64(latency)
            while readPos < readEnd {
                if isCancelled?() == true { throw Failure.cancelled }
                let want = Int(min(Int64(chunkFrames), readEnd - readPos))
                let padded = Int((want + frameSize - 1) / frameSize) * frameSize
                let block = try reader.read(from: readPos, count: padded)
                var processed: [Float]
                if options.denoise {
                    processed = []
                    processed.reserveCapacity(padded)
                    var i = 0
                    while i < padded {
                        processed.append(contentsOf: processor.process(Array(block[i..<i + frameSize])))
                        i += frameSize
                    }
                    let mix = options.denoiseFloorMix
                    if mix > 0 {
                        let delayedDry = dryDelay + block
                        for k in 0..<padded {
                            processed[k] = processed[k] * (1 - mix) + delayedDry[k] * mix
                        }
                        dryDelay = Array(delayedDry.suffix(latency))
                    }
                } else {
                    processed = block
                }
                deEsser.process(&processed)
                tails.process(&processed)

                var out = processed[...]
                if toSkip > 0 {
                    let drop = min(toSkip, out.count)
                    out = out.dropFirst(drop)
                    toSkip -= drop
                }
                let remaining = Int(total - written)
                if out.count > remaining { out = out.prefix(remaining) }
                try writer.write(Array(out))
                written += Int64(out.count)
                readPos += Int64(padded)
                progress?(min(1, Double(written) / Double(max(total, 1))))
                if written >= total { break }
            }
            try writer.finish()
            try AtomicFile.replace(output, with: temp)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
