import Foundation

/// One four-track session. Always holds exactly four tracks.
public struct Project: Codable, Identifiable, Equatable, Sendable {
    public static let trackCount = 4

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Longest track, in seconds.
    public var durationSeconds: Double
    /// Restored on open.
    public var playheadSeconds: Double
    public var tracks: [Track]
    /// Developer Mode master volume (slider value, 0...1, unity at 0.75).
    public var masterVolume: Double
    /// Developer Mode metronome settings.
    public var metronome: MetronomeSettings
    /// How many lanes the project shows (1...4). New projects start with one;
    /// the "+" under the last lane reveals the next.
    public var visibleTrackCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        durationSeconds: Double = 0,
        playheadSeconds: Double = 0,
        tracks: [Track]? = nil,
        masterVolume: Double = MacroCurves.volumeUnitySlider,
        metronome: MetronomeSettings = MetronomeSettings(),
        visibleTrackCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.durationSeconds = durationSeconds
        self.playheadSeconds = playheadSeconds
        self.tracks = tracks ?? (0..<Project.trackCount).map { Track(index: $0) }
        self.masterVolume = masterVolume
        self.metronome = metronome
        self.visibleTrackCount = visibleTrackCount
        normalizeTracks()
    }

    /// Guarantees exactly four tracks with indices 0...3, whatever was decoded.
    public mutating func normalizeTracks() {
        var fixed: [Track] = []
        for i in 0..<Project.trackCount {
            if let existing = tracks.first(where: { $0.index == i }) {
                fixed.append(existing)
            } else {
                fixed.append(Track(index: i))
            }
        }
        tracks = fixed
        // Never hide a track that has audio.
        let lastRecorded = (tracks.lastIndex { !$0.isEmpty } ?? -1) + 1
        visibleTrackCount = min(Project.trackCount, max(1, visibleTrackCount, lastRecorded))
    }

    public var isAnySoloed: Bool { tracks.contains { $0.solo } }

    /// Whether a track is audible given mute and solo state.
    public func isAudible(_ index: Int) -> Bool {
        let track = tracks[index]
        if track.mute { return false }
        if isAnySoloed { return track.solo }
        return true
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, durationSeconds, playheadSeconds, tracks, masterVolume, metronome, visibleTrackCount
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        playheadSeconds = try c.decodeIfPresent(Double.self, forKey: .playheadSeconds) ?? 0
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        masterVolume = try c.decodeIfPresent(Double.self, forKey: .masterVolume) ?? MacroCurves.volumeUnitySlider
        metronome = try c.decodeIfPresent(MetronomeSettings.self, forKey: .metronome) ?? MetronomeSettings()
        visibleTrackCount = try c.decodeIfPresent(Int.self, forKey: .visibleTrackCount) ?? 1
        normalizeTracks()
    }
}

public struct MetronomeSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var bpm: Double
    /// 0, 1 or 2 bars of count-in before recording starts.
    public var countInBars: Int
    public var beatsPerBar: Int
    /// Slider value 0...1.
    public var volume: Double

    public init(enabled: Bool = false, bpm: Double = 100, countInBars: Int = 1, beatsPerBar: Int = 4, volume: Double = 0.6) {
        self.enabled = enabled
        self.bpm = bpm
        self.countInBars = countInBars
        self.beatsPerBar = beatsPerBar
        self.volume = volume
    }

    public static let bpmRange: ClosedRange<Double> = 40...240
}
