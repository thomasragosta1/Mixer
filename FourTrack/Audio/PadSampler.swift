import AVFoundation
import os
import FourTrackCore

/// Plays drum pads live: a small sampler that mixes its own voices inside one
/// source node. Each kit's one-shots (every recorded take of every pad) are
/// loaded once, repeated hits alternate takes, and voices follow the same
/// choke rules as the recorded drum track (`DrumVoicing`): hitting a drum again
/// fades out its previous ring, and the closed hat cuts off the open hat. So a
/// fast run of 808 kicks sounds like one kick re-struck instead of tails piling
/// up into distortion, and what you play is what gets recorded.
///
/// A tap only queues a note; the audio thread picks it up on its next cycle.
/// Nothing is ever started or stopped from the main thread, so a tap can't
/// block on the audio hardware. The output feeds a mixer routed into the armed
/// drum track's chain.
final class PadSampler {
    let mixer = AVAudioMixerNode()
    private let voices: PadVoices
    private let source: AVAudioSourceNode
    /// buffers[pad][variant]
    private var buffers: [[[Float]]] = []
    private var nextVariant: [Int] = Array(repeating: 0, count: DrumKit.padCount)
    private(set) var kit: DrumKit?
    private(set) var padSettings: [PadSettings] = []
    /// Track index whose chain the pads currently feed.
    var routedTrack = 0

    init() {
        let voices = PadVoices()
        self.voices = voices
        source = AVAudioSourceNode(format: EngineFormat.mono) { _, _, frameCount, audioBufferList -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            voices.render(into: data, frames: Int(frameCount))
            return noErr
        }
    }

    var nodes: [AVAudioNode] { [mixer, source] }

    func attach(to engine: AVAudioEngine) {
        engine.attach(mixer)
        engine.attach(source)
    }

    func connect(to chain: TrackChain, in engine: AVAudioEngine) {
        engine.connect(source, to: mixer, format: EngineFormat.mono)
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
            buffers[pad] = (0..<kit.variantCount).map { variant in
                PadProcessor.apply(kit.sample(pad: pad, variant: variant), settings[pad])
            }.filter { !$0.isEmpty }
        }
        self.kit = kit
        padSettings = settings
    }

    private static func normalized(_ pads: [PadSettings]) -> [PadSettings] {
        Array(pads.prefix(DrumKit.padCount)) + Array(repeating: .default, count: max(0, DrumKit.padCount - pads.count))
    }

    func trigger(_ pad: Int, velocity: Float) {
        guard let kit, buffers.indices.contains(pad), !buffers[pad].isEmpty else { return }
        let takes = buffers[pad]
        let samples = takes[nextVariant[pad] % takes.count]
        nextVariant[pad] += 1
        voices.queue(samples, gain: velocity, group: DrumVoicing.chokeGroup(kit: kit, pad: pad))
    }
}

/// The sampler's voices, shared between the main thread (which queues notes)
/// and the audio thread (which mixes them). The audio thread only ever tries
/// the lock, so it never waits on the main thread.
final class PadVoices: @unchecked Sendable {
    private struct Note {
        var samples: [Float]
        var gain: Float
        var group: Int
    }

    private struct Voice {
        var samples: [Float] = []
        var position = 0
        var gain: Float = 0
        var group = -1
        /// Frames left in the choke fade; nil while ringing normally.
        var fadeLeft: Int?
        var active: Bool { position < samples.count }
    }

    static let voiceCount = 16
    private let fadeFrames = max(1, Int((DrumVoicing.chokeFadeSeconds * EngineFormat.sampleRate).rounded()))
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let l = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        l.initialize(to: os_unfair_lock())
        return l
    }()
    private var pending: [Note] = []
    private var voices = [Voice](repeating: Voice(), count: PadVoices.voiceCount)
    private var nextVoice = 0

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Main thread: a pad was hit.
    func queue(_ samples: [Float], gain: Float, group: Int) {
        os_unfair_lock_lock(lock)
        if pending.count < 64 { pending.append(Note(samples: samples, gain: gain, group: group)) }
        os_unfair_lock_unlock(lock)
    }

    /// Audio thread: mixes every ringing voice into `out`.
    func render(into out: UnsafeMutablePointer<Float>, frames: Int) {
        out.update(repeating: 0, count: frames)
        if os_unfair_lock_trylock(lock) {
            for note in pending { start(note) }
            pending.removeAll(keepingCapacity: true)
            os_unfair_lock_unlock(lock)
        }
        for v in voices.indices where voices[v].active {
            mix(&voices[v], into: out, frames: frames)
        }
    }

    private func start(_ note: Note) {
        // Same drum (or the other hi-hat) still ringing: fade it out now.
        for v in voices.indices where voices[v].active && voices[v].group == note.group && voices[v].fadeLeft == nil {
            voices[v].fadeLeft = fadeFrames
        }
        // A free voice, else the one closest to finishing.
        let free = voices.indices.first { !voices[$0].active }
            ?? voices.indices.min { (voices[$0].samples.count - voices[$0].position) < (voices[$1].samples.count - voices[$1].position) }
            ?? 0
        voices[free] = Voice(samples: note.samples, position: 0, gain: note.gain, group: note.group, fadeLeft: nil)
    }

    private func mix(_ voice: inout Voice, into out: UnsafeMutablePointer<Float>, frames: Int) {
        let count = voice.samples.count
        var position = voice.position
        var fadeLeft = voice.fadeLeft
        let gain = voice.gain
        let fade = fadeFrames
        voice.samples.withUnsafeBufferPointer { s in
            for i in 0..<frames {
                guard position < count else { break }
                var g = gain
                if let left = fadeLeft {
                    if left <= 0 { position = count; break }
                    g *= Float(left) / Float(fade + 1)
                    fadeLeft = left - 1
                }
                out[i] += s[position] * g
                position += 1
            }
        }
        voice.position = position
        voice.fadeLeft = fadeLeft
        if position >= count { voice.samples = [] ; voice.position = 0 }
    }
}
