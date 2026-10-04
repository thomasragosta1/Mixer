import AVFoundation
import FourTrackCore

/// Plays drum pads live. Each kit's eight one-shots are rendered once into
/// buffers; a small pool of player nodes gives polyphony so fast or
/// overlapping hits don't cut each other off. The pool feeds a mixer that
/// is routed into the armed drum track's chain.
final class PadSampler {
    let mixer = AVAudioMixerNode()
    private let voices: [AVAudioPlayerNode] = (0..<10).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private var buffers: [AVAudioPCMBuffer] = []
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
        buffers = (0..<DrumKit.padCount).compactMap { pad in
            let samples = kit.sample(pad: pad)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: EngineFormat.mono, frameCapacity: AVAudioFrameCount(samples.count)),
                  let out = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { src in
                out.update(from: src.baseAddress!, count: samples.count)
            }
            return buffer
        }
    }

    func trigger(_ pad: Int, velocity: Float) {
        guard buffers.indices.contains(pad) else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.stop()
        voice.volume = velocity
        voice.scheduleBuffer(buffers[pad], at: nil, options: [], completionHandler: nil)
        voice.play()
    }
}
