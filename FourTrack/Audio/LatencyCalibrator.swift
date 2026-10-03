import AVFoundation
import FourTrackCore

/// "Calibrate" helper: plays clicks, records them back through the mic, and
/// measures how late they arrive relative to when they were rendered. The
/// result is the full round-trip compensation for the current route.
@MainActor
enum LatencyCalibrator {
    static let clickCount = 6
    static let bpm = 100.0

    enum Failure: LocalizedError {
        case notHeard
        var errorDescription: String? {
            "Couldn't hear the clicks. Turn the volume up, or hold the headphones next to the microphone, and try again."
        }
    }

    /// Returns the measured compensation in seconds.
    static func run(engine: MixerEngine, scratchURL: URL, route: AudioRouteKind) async throws -> Double {
        var silent = Project(name: "Calibration")
        for i in silent.tracks.indices { silent.tracks[i].mute = true }
        let clicks = MetronomeSettings(enabled: true, bpm: bpm, countInBars: 0, beatsPerBar: 1, volume: 1)

        _ = try engine.startRecording(
            trackIndex: 0,
            from: 0,
            project: silent,
            scratchURL: scratchURL,
            latency: 0,
            route: route,
            metronome: clicks
        )
        let beatSeconds = 60 / bpm
        try await Task.sleep(nanoseconds: UInt64((Double(clickCount) * beatSeconds + 0.6) * 1_000_000_000))
        guard let result = engine.stopRecording() else { throw Failure.notHeard }
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let placement = result.plan.placement(firstSampleHost: result.sink.firstSampleHostTime)
        let url = result.sink.url
        let count = clickCount
        let tempo = bpm
        let delay: Int? = try await Task.detached(priority: .userInitiated) {
            let reader = try CAFReader(url: url)
            let all = try reader.read(from: placement.skip, count: Int(max(0, reader.frameCount - placement.skip)))
            let sampleRate = CAFFormat.defaultSampleRate
            let clickFrames = ClickTrack.beats(from: 0, to: Int64(Double(count) * beatSeconds * sampleRate), bpm: tempo, beatsPerBar: 1)
                .map { Int($0.frame) }
            return LatencyCalibration.measureDelay(
                recorded: all,
                clickFrames: clickFrames,
                template: ClickTrack.click(accent: true),
                maxDelayFrames: Int(0.4 * sampleRate)
            )
        }.value
        guard let delay else { throw Failure.notHeard }
        return Double(delay) / CAFFormat.defaultSampleRate
    }
}
