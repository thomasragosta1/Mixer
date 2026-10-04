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
    static func render(input: URL, output: URL, progress: (Double) -> Void, isCancelled: () -> Bool) throws {
        let file = try AVAudioFile(forReading: input, commonFormat: .pcmFormatFloat32, interleaved: false)
        let total = file.length
        guard total > 0 else { throw Failure.renderFailed }

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
        player.scheduleFile(file, at: nil)
        player.play()

        let latencyFrames = AVAudioFramePosition((effect.auAudioUnit.latency * mono.sampleRate).rounded())
        let renderTotal = total + latencyFrames
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw Failure.renderFailed
        }
        let writer = try CAFWriter(url: output, sampleRate: mono.sampleRate)
        var toSkip = latencyFrames
        var written: AVAudioFramePosition = 0
        var outEnergy: Double = 0
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
                let keep = Int(min(AVAudioFramePosition(chunk.count), total - written))
                let samples = Array(chunk.prefix(keep))
                for s in samples { outEnergy += Double(s * s) }
                try writer.write(samples)
                written += AVAudioFramePosition(keep)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw Failure.renderFailed
            @unknown default:
                throw Failure.renderFailed
            }
            progress(Double(engine.manualRenderingSampleTime) / Double(renderTotal))
        }
        try writer.finish()
        // A model that failed to load passes silence; treat that as a failure so
        // Cleanup falls back instead of erasing the take.
        if written > 0 && outEnergy / Double(written) < 1e-12 { throw Failure.silentOutput }
    }
}
