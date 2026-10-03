import Foundation

/// Overwrite-anywhere: replaces samples of a track from a start point for the
/// length of a new recording, keeping everything before and after.
///
/// The result is written to a temporary file next to the track and moved over
/// the original with an atomic rename, so a crash mid-splice leaves the old
/// take untouched.
public enum Splicer {
    public static let defaultCrossfadeSeconds = 0.005
    static let chunkFrames = 65_536

    public struct Request {
        /// Existing take, or nil when the track is empty.
        public var trackURL: URL?
        /// Destination for the spliced take (may equal `trackURL`).
        public var destinationURL: URL
        /// Raw recording captured from the input tap.
        public var recordingURL: URL
        /// Frames to drop from the start of the recording (latency compensation
        /// and any audio captured before the timeline start point).
        public var recordingSkipFrames: Int64
        /// Frames of the recording to use after skipping; nil = all remaining.
        public var recordingFrameLimit: Int64?
        /// Timeline frame where the replaced region begins. Negative values drop
        /// the part of the recording that would land before 0.
        public var insertFrame: Int64
        public var crossfadeFrames: Int
        /// Digital trim applied to the new audio (Developer Mode input gain).
        public var inputGainDB: Double
        public var sampleRate: Double

        public init(
            trackURL: URL?,
            destinationURL: URL,
            recordingURL: URL,
            recordingSkipFrames: Int64 = 0,
            recordingFrameLimit: Int64? = nil,
            insertFrame: Int64,
            crossfadeFrames: Int = Int(Splicer.defaultCrossfadeSeconds * CAFFormat.defaultSampleRate),
            inputGainDB: Double = 0,
            sampleRate: Double = CAFFormat.defaultSampleRate
        ) {
            self.trackURL = trackURL
            self.destinationURL = destinationURL
            self.recordingURL = recordingURL
            self.recordingSkipFrames = recordingSkipFrames
            self.recordingFrameLimit = recordingFrameLimit
            self.insertFrame = insertFrame
            self.crossfadeFrames = crossfadeFrames
            self.inputGainDB = inputGainDB
            self.sampleRate = sampleRate
        }
    }

    public struct Result: Equatable {
        /// Total frames in the new take.
        public var frameCount: Int64
        /// Timeline region that now holds new audio, [start, end).
        public var replacedStart: Int64
        public var replacedEnd: Int64
    }

    @discardableResult
    public static func splice(_ request: Request) throws -> Result {
        let recording = try CAFReader(url: request.recordingURL)
        let existing = try request.trackURL.flatMap { url -> CAFReader? in
            FileManager.default.fileExists(atPath: url.path) ? try CAFReader(url: url) : nil
        }
        let existingFrames = existing?.frameCount ?? 0

        // Resolve which part of the recording lands where on the timeline.
        var skip = max(0, request.recordingSkipFrames)
        var insert = request.insertFrame
        if insert < 0 {
            skip += -insert
            insert = 0
        }
        var newFrames = max(0, recording.frameCount - skip)
        if let limit = request.recordingFrameLimit {
            newFrames = min(newFrames, max(0, limit))
        }
        let replacedEnd = insert + newFrames
        let total = newFrames > 0 ? max(existingFrames, replacedEnd) : existingFrames
        let fade = min(max(0, request.crossfadeFrames), Int(newFrames / 2))
        let gain = Float(MacroCurves.dbToGain(request.inputGainDB))

        let tempURL = request.destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(request.destinationURL.lastPathComponent).splice-\(UUID().uuidString)")
        let writer = try CAFWriter(url: tempURL, sampleRate: request.sampleRate)
        do {
            var frame: Int64 = 0
            while frame < total {
                let n = Int(min(Int64(chunkFrames), total - frame))
                var out = try existing?.read(from: frame, count: n) ?? [Float](repeating: 0, count: n)
                // Overlap of this chunk with the replaced region.
                let lo = max(frame, insert)
                let hi = min(frame + Int64(n), replacedEnd)
                if hi > lo {
                    let fresh = try recording.read(from: skip + (lo - insert), count: Int(hi - lo))
                    for k in 0..<fresh.count {
                        let t = lo + Int64(k)
                        let i = Int(t - frame)
                        let r = fresh[k] * gain
                        let (oldW, newW) = weights(position: t - insert, length: newFrames, fade: fade)
                        out[i] = out[i] * oldW + r * newW
                    }
                }
                try writer.write(out)
                frame += Int64(n)
            }
            try writer.finish()
            try AtomicFile.replace(request.destinationURL, with: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
        return Result(frameCount: total, replacedStart: insert, replacedEnd: replacedEnd)
    }

    /// Equal-power crossfade weights inside the replaced region: the new audio
    /// fades in over the first `fade` frames and out over the last `fade`
    /// frames while the old take fades the opposite way.
    @inline(__always)
    static func weights(position p: Int64, length: Int64, fade: Int) -> (old: Float, new: Float) {
        guard fade > 0 else { return (0, 1) }
        let f = Int64(fade)
        var x: Float = 1
        if p < f {
            x = (Float(p) + 0.5) / Float(fade)
        } else if p >= length - f {
            x = (Float(length - p) - 0.5) / Float(fade)
        }
        if x >= 1 { return (0, 1) }
        let angle = x * .pi / 2
        return (cos(angle), sin(angle))
    }
}
