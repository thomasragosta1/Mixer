import AVFoundation
import FourTrackCore

/// Click track: a bar-accented click on the timeline grid, plus an optional
/// count-in before recording. Audio is rendered in short consecutive chunks,
/// so it runs indefinitely and tempo or time-signature changes take effect
/// within a fraction of a second while it keeps going: the beat continues
/// from where it was and simply speeds up or slows down.
final class Metronome {
    let player = AVAudioPlayerNode()
    private let accent = ClickTrack.click(accent: true)
    private let normal = ClickTrack.click(accent: false)
    private var settings = MetronomeSettings()
    private var nextChunkStart: Int64 = 0
    private var generation = 0
    /// Beat grid: beat number `anchorBeat` falls on timeline frame `anchorFrame`.
    private(set) var anchorFrame: Int64 = 0
    private(set) var anchorBeat: Double = 0
    /// Click tails that run past the end of the previous chunk.
    private var carry: [Float] = []
    /// 0.2 s chunks, two queued: a change is heard within about 0.4 s.
    static let chunkFrames: Int64 = 9_600
    static let queuedChunks = 2

    func attach(to engine: AVAudioEngine) {
        engine.attach(player)
    }

    func connect(in engine: AVAudioEngine) {
        let bus = engine.mainMixerNode.nextAvailableInputBus
        engine.connect(player, to: engine.mainMixerNode, fromBus: 0, toBus: bus, format: EngineFormat.mono)
    }

    /// Starts clicking from timeline frame `fromFrame` (may be negative for a
    /// count-in) at `hostTime`, on a grid anchored at timeline 0.
    func start(fromFrame: Int64, at hostTime: UInt64, settings: MetronomeSettings) {
        stop()
        self.settings = settings
        player.volume = Float(MacroCurves.metronomeGain(settings.volume))
        anchorFrame = 0
        anchorBeat = 0
        carry = []
        generation += 1
        nextChunkStart = fromFrame
        for _ in 0..<Metronome.queuedChunks { scheduleNextChunk(generation: generation) }
        player.play(at: AVAudioTime(hostTime: hostTime))
    }

    func stop() {
        generation += 1
        player.stop()
    }

    /// Changes tempo / time signature / volume without stopping. The new tempo
    /// starts at the next chunk, continuing the beat from where it is.
    /// Returns the new grid anchor (timeline frame, beat number) for the beat lights.
    @discardableResult
    func update(settings new: MetronomeSettings) -> (frame: Int64, beat: Double) {
        if new.bpm != settings.bpm {
            let beatAtNext = beat(at: nextChunkStart)
            anchorFrame = nextChunkStart
            anchorBeat = beatAtNext
        }
        settings = new
        player.volume = Float(MacroCurves.metronomeGain(new.volume))
        return (anchorFrame, anchorBeat)
    }

    private var framesPerBeat: Double { ClickTrack.framesPerBeat(bpm: settings.bpm) }

    private func beat(at frame: Int64) -> Double {
        anchorBeat + Double(frame - anchorFrame) / framesPerBeat
    }

    private func scheduleNextChunk(generation gen: Int) {
        guard gen == generation, let buffer = renderChunk(from: nextChunkStart) else { return }
        nextChunkStart += Metronome.chunkFrames
        player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleNextChunk(generation: gen)
            }
        }
    }

    private func renderChunk(from start: Int64) -> AVAudioPCMBuffer? {
        let count = Int(Metronome.chunkFrames)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: EngineFormat.mono, frameCapacity: AVAudioFrameCount(count)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(count)
        var local = [Float](repeating: 0, count: count + accent.count)
        for (i, v) in carry.enumerated() where i < local.count { local[i] += v }
        // Beats that start inside this chunk, on the current grid.
        let fpb = framesPerBeat
        var k = (beat(at: start)).rounded(.up)
        let bar = Double(max(1, settings.beatsPerBar))
        while true {
            let frame = anchorFrame + Int64(((k - anchorBeat) * fpb).rounded())
            let offset = Int(frame - start)
            if offset >= count { break }
            if offset >= 0 {
                let isAccent = (k.truncatingRemainder(dividingBy: bar) + bar).truncatingRemainder(dividingBy: bar) == 0
                let click = isAccent ? accent : normal
                for (j, v) in click.enumerated() { local[offset + j] += v }
            }
            k += 1
        }
        for i in 0..<count { out[i] = local[i] }
        carry = Array(local[count...])
        return buffer
    }
}
