import AVFoundation
import AudioToolbox
import FourTrackCore

/// Cleanup's denoise stage. Prefers Apple's on-device Voice Isolation model
/// (the Audio Unit behind FaceTime's "Voice Isolation" mic mode, built into
/// iOS 16+; free to use, nothing to bundle). Removes noise, room and backing-
/// track bleed much more strongly than RNNoise. Falls back to the RNNoise
/// pipeline if the unit is missing or misbehaves on a device.
enum CleanupEngine {
    static func render(input: URL, output: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws {
        if VoiceIsolation.isAvailable {
            let isolated = output.deletingLastPathComponent()
                .appendingPathComponent(".\(output.lastPathComponent).isolated-\(UUID().uuidString).caf")
            defer { try? FileManager.default.removeItem(at: isolated) }
            do {
                try VoiceIsolation.render(input: input, output: isolated, progress: { progress($0 * 0.85) }, isCancelled: isCancelled)
                var options = CleanupPipeline.Options()
                options.denoise = false
                try CleanupPipeline(options: options).render(
                    input: isolated, output: output,
                    progress: { progress(0.85 + $0 * 0.15) }, isCancelled: isCancelled
                )
                return
            } catch let error as CleanupPipeline.Failure {
                throw error
            } catch {
                // Fall through to RNNoise.
            }
        }
        try CleanupPipeline().render(input: input, output: output, progress: progress, isCancelled: isCancelled)
    }
}

enum VoiceIsolation {
    enum Failure: Error { case unavailable, unsupportedFormat, renderFailed, silentOutput }

    /// kAudioUnitSubType_AUSoundIsolation ('vois').
    static let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0x766F_6973,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    /// kAUSoundIsolationParam_WetDryMixPercent. 95% keeps a trace of the
    /// original underneath so the result never sounds hollow.
    static let wetDryParam: AudioUnitParameterID = 0
    static let wetDryPercent: Float = 95

    static var isAvailable: Bool {
        var d = description
        return AudioComponentFindNext(nil, &d) != nil
    }

    /// Runs the take through the unit offline. Output is time-aligned with
    /// the input (the unit's reported latency is removed) and the same length.
    ///
    /// The model is the slow part, so a take is split into segments rendered
    /// in parallel, each on its own engine. Each segment starts a second early
    /// (thrown away) so the model has settled by the join, and runs 20 ms past
    /// its end for a crossfade into the next one, so joins are inaudible.
    static func render(input: URL, output: URL, progress: @escaping (Double) -> Void, isCancelled: @escaping () -> Bool) throws {
        let total = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false).length
        guard total > 0 else { throw Failure.renderFailed }
        let sampleRate = EngineFormat.sampleRate
        let preroll = AVAudioFramePosition(sampleRate * 1.0)
        let crossfade = AVAudioFramePosition(sampleRate * 0.02)
        // Segments of at least 8 s, one per spare core, at most 4.
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        let count = max(1, min(4, cores, Int(Double(total) / (sampleRate * 8))))
        let bounds = (0...count).map { AVAudioFramePosition(Double(total) * Double($0) / Double(count)) }

        let lock = NSLock()
        var segmentProgress = [Double](repeating: 0, count: count)
        var results = [Result<(samples: [Float], energy: Double), Error>?](repeating: nil, count: count)
        DispatchQueue.concurrentPerform(iterations: count) { k in
            let start = bounds[k]
            let end = k == count - 1 ? total : min(total, bounds[k + 1] + crossfade)
            let result = Result {
                try renderSegment(input: input, from: start, to: end, preroll: preroll, isCancelled: isCancelled) { p in
                    let overall: Double = lock.withLock {
                        segmentProgress[k] = p
                        return segmentProgress.reduce(0, +) / Double(count)
                    }
                    progress(overall)
                }
            }
            lock.withLock { results[k] = result }
        }

        // Join the segments, crossfading each one's extra tail into the next.
        let writer = try CAFWriter(url: output, sampleRate: sampleRate)
        var carry: [Float] = []
        var energy: Double = 0
        for k in 0..<count {
            guard let result = results[k] else { throw Failure.renderFailed }
            let segment = try result.get()
            energy += segment.energy
            var samples = segment.samples
            let fade = min(carry.count, samples.count)
            for i in 0..<fade {
                let t = Float(i + 1) / Float(fade + 1)
                samples[i] = carry[i] * (1 - t) + samples[i] * t
            }
            let keep = k == count - 1 ? samples.count : max(0, samples.count - Int(crossfade))
            try writer.write(Array(samples[0..<keep]))
            carry = Array(samples[keep...])
        }
        try writer.finish()
        // A model that failed to load passes silence; treat that as a failure so
        // Cleanup falls back instead of erasing the take.
        if energy / Double(total) < 1e-12 { throw Failure.silentOutput }
    }

    /// Renders input frames [start, end) through its own engine and unit,
    /// warming the model up on `preroll` frames before `start`.
    private static func renderSegment(
        input: URL,
        from start: AVAudioFramePosition,
        to end: AVAudioFramePosition,
        preroll: AVAudioFramePosition,
        isCancelled: () -> Bool,
        progress: (Double) -> Void
    ) throws -> (samples: [Float], energy: Double) {
        let file = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        let readStart = max(0, start - preroll)
        let readFrames = end - readStart
        guard readFrames > 0 else { return ([], 0) }

        let effect = AVAudioUnitEffect(audioComponentDescription: description)
        // Agree on a format up front: bus formats throw Swift errors, whereas a
        // rejected engine connection raises an Objective-C exception.
        let mono = EngineFormat.mono
        let stereo = EngineFormat.stereo
        var format: AVAudioFormat?
        for candidate in [mono, stereo] {
            do {
                try effect.auAudioUnit.inputBusses[0].setFormat(candidate)
                try effect.auAudioUnit.outputBusses[0].setFormat(candidate)
                format = candidate
                break
            } catch {
                continue
            }
        }
        guard let format else { throw Failure.unsupportedFormat }
        AudioUnitSetParameter(effect.audioUnit, wetDryParam, kAudioUnitScope_Global, 0, wetDryPercent, 0)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: mono, maximumFrameCount: 4_096)
        try engine.start()
        defer { engine.stop() }
        player.scheduleSegment(file, startingFrame: readStart, frameCount: AVAudioFrameCount(readFrames), at: nil)
        player.play()

        let latencyFrames = AVAudioFramePosition((effect.auAudioUnit.latency * mono.sampleRate).rounded())
        let renderTotal = readFrames + latencyFrames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw Failure.renderFailed
        }
        let wanted = Int(end - start)
        var out: [Float] = []
        out.reserveCapacity(wanted)
        var toSkip = latencyFrames + (start - readStart)
        var energy: Double = 0
        while engine.manualRenderingSampleTime < renderTotal {
            if isCancelled() { throw CleanupPipeline.Failure.cancelled }
            let remaining = renderTotal - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                guard let data = buffer.floatChannelData?[0] else { throw Failure.renderFailed }
                var chunk = UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))[...]
                if toSkip > 0 {
                    let drop = min(Int(toSkip), chunk.count)
                    chunk = chunk.dropFirst(drop)
                    toSkip -= AVAudioFramePosition(drop)
                }
                let keep = min(chunk.count, wanted - out.count)
                for s in chunk.prefix(keep) {
                    energy += Double(s * s)
                    out.append(s)
                }
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw Failure.renderFailed
            @unknown default:
                throw Failure.renderFailed
            }
            progress(Double(engine.manualRenderingSampleTime) / Double(renderTotal))
        }
        // The unit can end a few frames short; pad so the take keeps its length.
        if out.count < wanted { out.append(contentsOf: repeatElement(0, count: wanted - out.count)) }
        return (out, energy)
    }
}
