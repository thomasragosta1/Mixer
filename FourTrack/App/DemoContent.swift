import Foundation
import FourTrackCore

/// App Store screenshots: launched with `-demoContent YES`, the app uses a
/// separate, freshly seeded set of projects (it never touches real ones).
/// The audio is synthesized so the waveforms look like real parts.
enum DemoContent {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "demoContent") }

    static func makeStore(root: URL) throws -> ProjectStore {
        try? FileManager.default.removeItem(at: root)
        let store = try ProjectStore(rootURL: root)
        let now = Date()

        // Older first, so the list reads newest at the top.
        try seed(store, name: "Voice Note – Bridge Idea", mode: .simple, daysAgo: 9, now: now,
                 parts: [("Track 1", .vocal, 38)])
        try seed(store, name: "Kitchen Jam", mode: .simple, daysAgo: 6, now: now,
                 parts: [("Guitar", .strum, 64), ("Shaker", .pulse, 64)])
        try seed(store, name: "Chorus Harmony", mode: .full, daysAgo: 3, now: now,
                 parts: [("Lead", .vocal, 52), ("High Harmony", .vocal, 52), ("Low Harmony", .vocal, 50)])
        try seed(store, name: "Late Night Demo", mode: .full, daysAgo: 0, now: now,
                 parts: [("Acoustic", .strum, 96), ("Vocal", .vocal, 92), ("Bass", .bass, 96)])
        return store
    }

    private enum Part { case strum, vocal, bass, pulse }

    private static func seed(_ store: ProjectStore, name: String, mode: ProjectMode, daysAgo: Double, now: Date, parts: [(String, Part, Double)]) throws {
        let date = now.addingTimeInterval(-daysAgo * 86_400 - 3_600)
        var project = try store.create(name: name, mode: mode, now: date)
        for (i, part) in parts.enumerated() {
            let url = store.audioURL(project: project.id, track: i)
            let samples = synthesize(part.1, seconds: part.2, seed: UInt64(i + 1) &* 7919 &+ UInt64(name.count))
            let writer = try CAFWriter(url: url)
            try writer.write(samples)
            try writer.finish()
            try? PeakGenerator.write(PeakGenerator.peaks(of: samples), to: store.peaksURL(project: project.id, track: i))
            var track = Track(index: i, name: part.0)
            track.audioFileName = ProjectStore.audioFileName(track: i)
            project.tracks[i] = track
        }
        project.visibleTrackCount = max(1, parts.count)
        project.metronome.bpm = 92
        store.refreshDurations(&project)
        project.updatedAt = date
        try store.save(project)
    }

    /// Quiet noise shaped by a musical envelope: strummed chords on the beat,
    /// sung phrases with breaths, bass notes, a steady shaker.
    private static func synthesize(_ part: Part, seconds: Double, seed: UInt64) -> [Float] {
        let rate = CAFFormat.defaultSampleRate
        let count = Int(seconds * rate)
        let beat = 60.0 / 92.0
        var rng = seed | 1
        func noise() -> Float {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return Float(Double(rng % 20_000) / 10_000 - 1)
        }
        var out = [Float](repeating: 0, count: count)
        for n in 0..<count {
            let t = Double(n) / rate
            let env: Double
            switch part {
            case .strum:
                let inBeat = t.truncatingRemainder(dividingBy: beat)
                let accent = Int(t / beat) % 4 == 0 ? 1.0 : 0.7
                let section = 0.75 + 0.25 * sin(t / 9)
                env = accent * section * exp(-inBeat * 3.2)
            case .vocal:
                let phrase = 5.5
                let p = t.truncatingRemainder(dividingBy: phrase)
                let sung = p < 4.3 ? sin(Double.pi * p / 4.3) : 0
                let syllables = 0.65 + 0.35 * abs(sin(t * 5.3 + sin(t * 1.7)))
                env = t < 3 ? 0 : sung * syllables * (0.7 + 0.3 * sin(t / 11))
            case .bass:
                let inBeat = t.truncatingRemainder(dividingBy: beat * 2)
                env = t < beat * 8 ? 0 : 0.55 * exp(-inBeat * 1.2)
            case .pulse:
                let inHalf = t.truncatingRemainder(dividingBy: beat / 2)
                env = 0.3 * exp(-inHalf * 14)
            }
            out[n] = Float(env) * 0.5 * noise()
        }
        return out
    }
}
