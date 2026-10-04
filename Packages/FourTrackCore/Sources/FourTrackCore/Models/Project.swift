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
    /// Set when the project is moved to the bin; nil for live projects.
    public var deletedAt: Date?
    /// Top-to-bottom display order of the tracks (a permutation of 0...3).
    /// Track indices (and their audio files) never change; only the order does.
    public var laneOrder: [Int]

    /// Track indices of the lanes on screen, top to bottom.
    public var visibleLanes: [Int] { Array(laneOrder.prefix(visibleTrackCount)) }

    /// Reorders visible lanes (List.onMove semantics).
    public mutating func moveLanes(fromOffsets source: IndexSet, toOffset destination: Int) {
        var visible = visibleLanes
        let moving = source.sorted().map { visible[$0] }
        for offset in source.sorted(by: >) { visible.remove(at: offset) }
        let insertAt = destination - source.filter { $0 < destination }.count
        visible.insert(contentsOf: moving, at: max(0, min(insertAt, visible.count)))
        laneOrder = visible + laneOrder.dropFirst(visibleTrackCount)
    }

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
        self.deletedAt = nil
        self.laneOrder = Array(0..<Project.trackCount)
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
        // Lane order must be a permutation of 0...3.
        var seen = Set<Int>()
        laneOrder = laneOrder.filter { (0..<Project.trackCount).contains($0) && seen.insert($0).inserted }
        laneOrder += (0..<Project.trackCount).filter { !seen.contains($0) }
        // Never hide a track that has audio.
        let lastRecorded = tracks.filter { !$0.isEmpty }.compactMap { laneOrder.firstIndex(of: $0.index) }.max().map { $0 + 1 } ?? 0
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
        case id, name, createdAt, updatedAt, durationSeconds, playheadSeconds, tracks, masterVolume, metronome, visibleTrackCount, deletedAt, laneOrder
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
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        laneOrder = try c.decodeIfPresent([Int].self, forKey: .laneOrder) ?? Array(0..<Project.trackCount)
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
