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
    private(set) var padSettings: [PadSettings] = []
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

    /// Loads a kit with per-pad settings. Only pads whose sound changed are rebuilt.
    func load(kit: DrumKit, pads: [PadSettings] = []) {
        let settings = Self.normalized(pads)
        if kit == self.kit && settings == padSettings { return }
        let kitChanged = kit != self.kit
        if kitChanged || buffers.count != DrumKit.padCount {
            buffers = Array(repeating: [], count: DrumKit.padCount)
            nextVariant = Array(repeating: 0, count: DrumKit.padCount)
        }
        for pad in 0..<DrumKit.padCount where kitChanged || padSettings.count != DrumKit.padCount || padSettings[pad] != settings[pad] || buffers[pad].isEmpty {
            buffers[pad] = (0..<kit.variantCount).compactMap { variant in
                Self.makeBuffer(PadProcessor.apply(kit.sample(pad: pad, variant: variant), settings[pad]))
            }
        }
        self.kit = kit
        padSettings = settings
    }

    private static func normalized(_ pads: [PadSettings]) -> [PadSettings] {
        Array(pads.prefix(DrumKit.padCount)) + Array(repeating: .default, count: max(0, DrumKit.padCount - pads.count))
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
        voice.volume = velocity
        // Voices keep running (silent when idle), so a hit only schedules its
        // buffer, replacing whatever that voice was still playing. Stopping and
        // restarting a player on every tap made the main thread wait for the
        // audio hardware, which froze the app when the hardware stalled.
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !voice.isPlaying { voice.play() }
    }

    /// Starts every voice idling, right after the engine (re)starts, so taps
    /// never have to start a player themselves.
    func startVoices() {
        for voice in voices where !voice.isPlaying && voice.engine?.isRunning == true {
            voice.play()
        }
    }
}
