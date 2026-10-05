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
    /// Metronome: mode, tempo, time signature, count-in.
    public var metronome: MetronomeSettings
    /// How many lanes the project shows (1...4). New projects start with one;
    /// the "+" under the last lane reveals the next.
    public var visibleTrackCount: Int
    /// Set when the project is moved to the bin; nil for live projects.
    public var deletedAt: Date?
    /// Top-to-bottom display order of the tracks (a permutation of 0...3).
    /// Track indices (and their audio files) never change; only the order does.
    public var laneOrder: [Int]
    /// The project's own "Recently Deleted": tracks removed from the lanes,
    /// newest last, with their audio kept until deleted for good.
    public var deletedTracks: [DeletedTrack]
    /// Simple projects show only the basic recording features; Full shows everything.
    public var mode: ProjectMode

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
        visibleTrackCount: Int = 1,
        mode: ProjectMode = .full
    ) {
        self.mode = mode
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
        self.deletedTracks = []
        normalizeTracks()
    }

    /// Clears a lane's slot and takes it off screen. The remaining lanes keep
    /// their order; the freed slot goes after them, ready for "+".
    public mutating func removeLane(_ index: Int) {
        let visible = visibleLanes.filter { $0 != index }
        let hidden = laneOrder.filter { $0 != index && !visible.contains($0) }
        tracks[index] = Track(index: index)
        if visible.isEmpty {
            // Always keep one lane on screen.
            laneOrder = [index] + hidden
            visibleTrackCount = 1
        } else {
            laneOrder = visible + [index] + hidden
            visibleTrackCount = visible.count
        }
    }

    /// Slot a recovered track can go into: an empty lane on screen first,
    /// then the next hidden one. nil when all four lanes hold audio.
    public func freeSlotForRecovery() -> Int? {
        if let empty = visibleLanes.first(where: { tracks[$0].isEmpty && tracks[$0].drumHits.isEmpty }) {
            return empty
        }
        guard visibleTrackCount < Project.trackCount else { return nil }
        return laneOrder[visibleTrackCount]
    }

    /// Puts a track into `slot` and makes sure its lane is on screen.
    public mutating func placeRecovered(_ track: Track, in slot: Int) {
        var t = track
        t.index = slot
        tracks[slot] = t
        if !visibleLanes.contains(slot) {
            let visible = visibleLanes
            laneOrder = visible + [slot] + laneOrder.filter { $0 != slot && !visible.contains($0) }
            visibleTrackCount = visible.count + 1
        }
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
        case id, name, createdAt, updatedAt, durationSeconds, playheadSeconds, tracks, masterVolume, metronome, visibleTrackCount, deletedAt, laneOrder, deletedTracks, mode
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
        deletedTracks = try c.decodeIfPresent([DeletedTrack].self, forKey: .deletedTracks) ?? []
        // Projects from before Simple mode keep every feature they had.
        mode = ((try? c.decodeIfPresent(ProjectMode.self, forKey: .mode)) ?? nil) ?? .full
        normalizeTracks()
    }
}

/// How much of the app a project shows.
public enum ProjectMode: String, Codable, Sendable {
    /// Just recording audio: tracks with a volume bar and Clean Up, export.
    /// No drum tracks, mixer, mute/solo, metronome or quantize.
    case simple
    /// Everything.
    case full
}

extension Project {
    /// True when the project uses something Simple mode hides, so switching back
    /// to Simple would hide settings that still change the sound. Volume and
    /// Clean Up are part of Simple mode.
    public var usesFullModeFeatures: Bool {
        if masterVolume != MacroCurves.volumeUnitySlider || metronome.enabled { return true }
        for t in tracks {
            if t.mute || t.solo || t.devOverrides != nil { return true }
            if t.eqLow != 0 || t.eqMid != 0 || t.eqHigh != 0 { return true }
            if t.compressor != Track.defaultCompressor || t.space != 0 || t.warmth != 0 { return true }
            if t.isDrums { return true }
        }
        return false
    }

    /// Drum tracks with something recorded on them. Simple mode has no drums,
    /// so these have to be deleted before a project can switch to Simple.
    public var drumTracksWithTakes: [Int] {
        visibleLanes.filter { tracks[$0].isDrums && (!tracks[$0].isEmpty || !tracks[$0].drumHits.isEmpty) }
    }

    /// Turns off everything Simple mode hides, so switching to Simple can't
    /// leave hidden settings changing the sound. Volume and Clean Up stay.
    /// Empty drum tracks become audio tracks; call only when
    /// `drumTracksWithTakes` is empty.
    public mutating func resetFullModeFeatures() {
        masterVolume = MacroCurves.volumeUnitySlider
        metronome.mode = .off
        for i in tracks.indices {
            var t = tracks[i]
            t.mute = false
            t.solo = false
            t.devOverrides = nil
            t.eqLow = 0; t.eqMid = 0; t.eqHigh = 0
            t.compressor = Track.defaultCompressor
            t.space = 0
            t.warmth = 0
            if t.isDrums && t.isEmpty && t.drumHits.isEmpty {
                t.kind = .audio
                if t.name == "Drums" { t.name = "Track \(i + 1)" }
            }
            tracks[i] = t
        }
    }

    /// Brings a project saved by an earlier version in line with today's
    /// Simple mode: a Simple project that already has drum takes becomes Full
    /// (so nothing is lost); otherwise its empty drum tracks become audio tracks.
    public mutating func migrateSimpleMode() {
        guard mode == .simple else { return }
        if !drumTracksWithTakes.isEmpty {
            mode = .full
            return
        }
        for i in tracks.indices where tracks[i].isDrums && tracks[i].isEmpty && tracks[i].drumHits.isEmpty {
            tracks[i].kind = .audio
            if tracks[i].name == "Drums" { tracks[i].name = "Track \(i + 1)" }
        }
    }
}

/// A track in a project's Recently Deleted. Its audio lives in the project
/// folder under `deleted-<id>` file names until recovered or deleted for good.
public struct DeletedTrack: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var track: Track
    public var deletedAt: Date

    public init(id: UUID = UUID(), track: Track, deletedAt: Date = Date()) {
        self.id = id
        self.track = track
        self.deletedAt = deletedAt
    }
}

/// Off, clicking, or silent with the beats shown on screen.
public enum MetronomeMode: String, Codable, CaseIterable, Sendable {
    case off
    case on
    /// No sound; the beat lights still pulse.
    case visual

    /// The next state for the metronome button: On → Visual → Off → On.
    public var next: MetronomeMode {
        switch self {
        case .off: return .on
        case .on: return .visual
        case .visual: return .off
        }
    }
}

public struct TimeSignature: Codable, Equatable, Hashable, Sendable {
    public var beats: Int
    /// 4 = quarter-note beats, 8 = eighth-note beats.
    public var unit: Int

    public init(_ beats: Int, _ unit: Int) {
        self.beats = beats
        self.unit = unit
    }

    public var label: String { "\(beats)/\(unit)" }

    /// Tapping the time signature cycles these.
    public static let quick: [TimeSignature] = [TimeSignature(4, 4), TimeSignature(3, 4), TimeSignature(2, 4)]
    /// Press and hold for these.
    public static let more: [TimeSignature] = [TimeSignature(5, 4), TimeSignature(6, 4), TimeSignature(6, 8), TimeSignature(7, 8), TimeSignature(9, 8), TimeSignature(12, 8)]

    /// The next quick signature after this one (an unusual one goes back to 4/4).
    public var nextQuick: TimeSignature {
        guard let i = TimeSignature.quick.firstIndex(of: self) else { return TimeSignature.quick[0] }
        return TimeSignature.quick[(i + 1) % TimeSignature.quick.count]
    }
}

public struct MetronomeSettings: Equatable, Sendable {
    public var mode: MetronomeMode
    /// Beats (of `beatUnit`) per minute.
    public var bpm: Double
    /// 0, 1 or 2 bars of count-in before recording starts.
    public var countInBars: Int
    public var beatsPerBar: Int
    public var beatUnit: Int
    /// Slider value 0...1.
    public var volume: Double
    /// BPM change for one tap on the tempo arrows (press and hold changes by 1).
    public var tempoStep: Double

    /// The metronome is running (clicking or visual-only).
    public var enabled: Bool {
        get { mode != .off }
        set { mode = newValue ? .on : .off }
    }

    public var timeSignature: TimeSignature {
        get { TimeSignature(beatsPerBar, beatUnit) }
        set { beatsPerBar = max(1, newValue.beats); beatUnit = newValue.unit }
    }

    public init(enabled: Bool = false, bpm: Double = MetronomeSettings.defaultBPM, countInBars: Int = 1, beatsPerBar: Int = 4, volume: Double = 0.6) {
        self.mode = enabled ? .on : .off
        self.bpm = bpm
        self.countInBars = countInBars
        self.beatsPerBar = beatsPerBar
        self.beatUnit = 4
        self.volume = volume
        self.tempoStep = MetronomeSettings.defaultTempoStep
    }

    public static let defaultBPM: Double = 120
    public static let defaultTempoStep: Double = 10
    public static let bpmRange: ClosedRange<Double> = 40...240
    public static let tempoStepRange: ClosedRange<Double> = 1...40

    /// Changes the tempo by `delta`, clamped to the allowed range.
    public mutating func nudgeTempo(by delta: Double) {
        bpm = min(max((bpm + delta).rounded(), MetronomeSettings.bpmRange.lowerBound), MetronomeSettings.bpmRange.upperBound)
    }

    /// Beat number within the bar (0-based) at a timeline position, on the click grid
    /// anchored at 0. Negative positions (count-in) work too.
    public func beatInBar(at seconds: Double) -> Int {
        let beat = Int((seconds * bpm / 60).rounded(.down))
        let n = max(1, beatsPerBar)
        return ((beat % n) + n) % n
    }

    /// How far through the current beat (0..<1), for the pulse animation.
    public func beatPhase(at seconds: Double) -> Double {
        let b = seconds * bpm / 60
        return b - b.rounded(.down)
    }
}

extension MetronomeSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case mode, enabled, bpm, countInBars, beatsPerBar, beatUnit, volume, tempoStep
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        if let mode = try? c.decodeIfPresent(MetronomeMode.self, forKey: .mode) {
            self.mode = mode
        } else {
            // Saved before the three-state button: a plain on/off.
            self.enabled = (try c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        }
        bpm = try c.decodeIfPresent(Double.self, forKey: .bpm) ?? MetronomeSettings.defaultBPM
        countInBars = try c.decodeIfPresent(Int.self, forKey: .countInBars) ?? 1
        beatsPerBar = try c.decodeIfPresent(Int.self, forKey: .beatsPerBar) ?? 4
        beatUnit = try c.decodeIfPresent(Int.self, forKey: .beatUnit) ?? 4
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.6
        tempoStep = try c.decodeIfPresent(Double.self, forKey: .tempoStep) ?? MetronomeSettings.defaultTempoStep
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(bpm, forKey: .bpm)
        try c.encode(countInBars, forKey: .countInBars)
        try c.encode(beatsPerBar, forKey: .beatsPerBar)
        try c.encode(beatUnit, forKey: .beatUnit)
        try c.encode(volume, forKey: .volume)
        try c.encode(tempoStep, forKey: .tempoStep)
    }
}
