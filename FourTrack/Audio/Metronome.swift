import AVFoundation
import FourTrackCore

/// Click track for Developer Mode: plays a bar-accented click aligned to the
/// timeline grid, plus an optional count-in before recording. Audio is
/// rendered in short consecutive buffers so it can run indefinitely.
final class Metronome {
    let player = AVAudioPlayerNode()
    private let accent = ClickTrack.click(accent: true)
    private let normal = ClickTrack.click(accent: false)
    private var settings = MetronomeSettings()
    private var nextChunkStart: Int64 = 0
    private var generation = 0
    static let chunkFrames: Int64 = 48_000 * 2

    func attach(to engine: AVAudioEngine) {
        engine.attach(player)
    }

    func connect(in engine: AVAudioEngine) {
        let bus = engine.mainMixerNode.nextAvailableInputBus
        engine.connect(player, to: engine.mainMixerNode, fromBus: 0, toBus: bus, format: EngineFormat.mono)
    }

    /// Starts clicking from timeline frame `fromFrame` (may be negative for a
    /// count-in) at `hostTime`.
    func start(fromFrame: Int64, at hostTime: UInt64, settings: MetronomeSettings) {
        stop()
        self.settings = settings
        player.volume = Float(MacroCurves.metronomeGain(settings.volume))
        generation += 1
        nextChunkStart = fromFrame
        // Two chunks ahead keeps the queue full; each completion schedules one more.
        scheduleNextChunk(generation: generation)
        scheduleNextChunk(generation: generation)
        player.play(at: AVAudioTime(hostTime: hostTime))
    }

    func stop() {
        generation += 1
        player.stop()
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
        let count = AVAudioFrameCount(Metronome.chunkFrames)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: EngineFormat.mono, frameCapacity: count),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = count
        for i in 0..<Int(count) { out[i] = 0 }
        let end = start + Metronome.chunkFrames
        // Include beats that began just before this chunk so their tails continue.
        let beats = ClickTrack.beats(from: start - Int64(accent.count), to: end, bpm: settings.bpm, beatsPerBar: settings.beatsPerBar)
        for beat in beats {
            let click = beat.accent ? accent : normal
            for (j, v) in click.enumerated() {
                let pos = beat.frame + Int64(j) - start
                if pos >= 0 && pos < Int64(count) {
                    out[Int(pos)] += v
                }
            }
        }
        return buffer
    }
}
