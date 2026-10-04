import AVFoundation
import FourTrackCore

/// Plays drum pads live. Each kit's one-shots (every recorded take of every
/// pad) are loaded once into buffers, and repeated hits alternate takes; a small pool of player nodes gives polyphony so fast or
/// overlapping hits don't cut each other off. The pool feeds a mixer that
/// is routed into the armed drum track's chain.
final class PadSampler {
    let mixer = AVAudioMixerNode()
    private let voices: [AVAudioPlayerNode] = (0..<10).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    /// buffers[pad][variant]
    private var buffers: [[AVAudioPCMBuffer]] = []
    private var nextVariant: [Int] = Array(repeating: 0, count: DrumKit.padCount)
    private(set) var kit: DrumKit?
    /// Track index whose chain the pads currently feed.
    var routedTrack = 0

    var nodes: [AVAudioNode] { [mixer] + voices }

    func attach(to engine: AVAudioEngine) {
        engine.attach(mixer)
        voices.forEach { engine.attach($0) }
    }

    func connect(to chain: TrackChain, in engine: AVAudioEngine) {
        for (i, voice) in voices.enumerated() {
            engine.connect(voice, to: mixer, fromBus: 0, toBus: i, format: EngineFormat.mono)
        }
        // Bus 0 and 1 of the chain's input mixer are the take and its Cleanup render.
        engine.connect(mixer, to: chain.cleanupMix, fromBus: 0, toBus: 2, format: EngineFormat.mono)
    }

    func load(kit: DrumKit) {
        guard kit != self.kit else { return }
        self.kit = kit
        buffers = (0..<DrumKit.padCount).map { pad in
            (0..<kit.variantCount).compactMap { variant in
                Self.makeBuffer(kit.sample(pad: pad, variant: variant))
            }
        }
        nextVariant = Array(repeating: 0, count: DrumKit.padCount)
    }

    private static func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: EngineFormat.mono, frameCapacity: AVAudioFrameCount(samples.count)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            out.update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }

    func trigger(_ pad: Int, velocity: Float) {
        guard buffers.indices.contains(pad), !buffers[pad].isEmpty else { return }
        let takes = buffers[pad]
        let buffer = takes[nextVariant[pad] % takes.count]
        nextVariant[pad] += 1
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = velocity
        voice.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        voice.play()
    }
}
