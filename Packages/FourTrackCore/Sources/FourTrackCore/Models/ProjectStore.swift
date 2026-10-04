import Foundation

/// Persists project metadata as JSON next to the project's audio files:
///
///     <root>/<project-id>/project.json
///     <root>/<project-id>/track1.caf ... track4.caf
///     <root>/<project-id>/track1.cleaned.caf
///     <root>/<project-id>/track1.peaks
///
/// `root` is `Application Support/Projects` in the app. Stateless apart from
/// its root URL, so it is safe to use from background tasks.
public final class ProjectStore: @unchecked Sendable {
    public let rootURL: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public init(rootURL: URL) throws {
        self.rootURL = rootURL
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    // MARK: Paths

    public func directory(for id: UUID) -> URL {
        rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func metadataURL(for id: UUID) -> URL {
        directory(for: id).appendingPathComponent("project.json")
    }

    public static func audioFileName(track index: Int) -> String { "track\(index + 1).caf" }
    public static func cleanedFileName(track index: Int) -> String { "track\(index + 1).cleaned.caf" }
    public static func peaksFileName(track index: Int) -> String { "track\(index + 1).peaks" }

    public func fileURL(_ name: String, in id: UUID) -> URL {
        directory(for: id).appendingPathComponent(name)
    }

    public func audioURL(project id: UUID, track index: Int) -> URL {
        fileURL(ProjectStore.audioFileName(track: index), in: id)
    }

    public func cleanedURL(project id: UUID, track index: Int) -> URL {
        fileURL(ProjectStore.cleanedFileName(track: index), in: id)
    }

    public func peaksURL(project id: UUID, track index: Int) -> URL {
        fileURL(ProjectStore.peaksFileName(track: index), in: id)
    }

    /// Scratch file the input tap writes into while recording.
    public func recordingTempURL(project id: UUID) -> URL {
        fileURL(".recording.caf", in: id)
    }

    // MARK: CRUD

    public func create(name: String? = nil, now: Date = Date()) throws -> Project {
        // New projects start in Simple mode; the ⋯ menu switches to Full.
        let project = Project(name: name ?? nextDefaultName(), createdAt: now, mode: .simple)
        try fm.createDirectory(at: directory(for: project.id), withIntermediateDirectories: true)
        try save(project)
        return project
    }

    public func save(_ project: Project) throws {
        let dir = directory(for: project.id)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let data = try encoder.encode(project)
        try data.write(to: metadataURL(for: project.id), options: .atomic)
    }

    public func load(id: UUID) throws -> Project {
        let data = try Data(contentsOf: metadataURL(for: id))
        return try decoder.decode(Project.self, from: data)
    }

    /// Live projects, newest first. Unreadable folders are skipped, never deleted.
    public func loadAll() -> [Project] {
        loadEverything().filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Projects in the bin, most recently deleted first.
    public func loadBin() -> [Project] {
        loadEverything().filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private func loadEverything() -> [Project] {
        guard let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { url -> Project? in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try? load(id: id)
        }
    }

    /// Moves a project to the bin. Nothing is removed from disk.
    public func moveToBin(id: UUID, now: Date = Date()) throws {
        var project = try load(id: id)
        project.deletedAt = now
        try save(project)
    }

    /// Takes a project back out of the bin.
    public func restore(id: UUID) throws {
        var project = try load(id: id)
        project.deletedAt = nil
        try save(project)
    }

    /// Permanently removes a project and its audio. Only the bin calls this.
    public func delete(id: UUID) throws {
        let dir = directory(for: id)
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
    }

    // MARK: Track bin

    public enum TrackBinError: Error, Equatable {
        case notFound
        /// All four lanes already hold audio.
        case noFreeLane
    }

    /// Moves a track's audio aside and its settings into the project's
    /// Recently Deleted, then clears its lane. The caller saves the project.
    public func binTrack(_ project: inout Project, index: Int, now: Date = Date()) throws {
        let id = UUID()
        var track = project.tracks[index]
        let dir = directory(for: project.id)
        func move(_ name: String?, to newName: String) throws -> String? {
            guard let name else { return nil }
            let from = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { return nil }
            try fm.moveItem(at: from, to: dir.appendingPathComponent(newName))
            return newName
        }
        track.audioFileName = try move(track.audioFileName, to: "deleted-\(id.uuidString).caf")
        track.cleanedFileName = try move(track.cleanedFileName, to: "deleted-\(id.uuidString).cleaned.caf")
        try? fm.removeItem(at: peaksURL(project: project.id, track: index))
        project.deletedTracks.append(DeletedTrack(id: id, track: track, deletedAt: now))
        project.removeLane(index)
        refreshDurations(&project)
    }

    /// Puts a deleted track back into a free lane; returns the lane's track index.
    @discardableResult
    public func recoverTrack(_ project: inout Project, id: UUID) throws -> Int {
        guard let entry = project.deletedTracks.first(where: { $0.id == id }) else { throw TrackBinError.notFound }
        guard let slot = project.freeSlotForRecovery() else { throw TrackBinError.noFreeLane }
        var track = entry.track
        let dir = directory(for: project.id)
        // Clear whatever an empty slot may still have on disk.
        for name in [ProjectStore.audioFileName(track: slot), ProjectStore.cleanedFileName(track: slot), ProjectStore.peaksFileName(track: slot)] {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
        if let name = track.audioFileName {
            let target = ProjectStore.audioFileName(track: slot)
            try fm.moveItem(at: dir.appendingPathComponent(name), to: dir.appendingPathComponent(target))
            track.audioFileName = target
        }
        if let name = track.cleanedFileName {
            let target = ProjectStore.cleanedFileName(track: slot)
            if (try? fm.moveItem(at: dir.appendingPathComponent(name), to: dir.appendingPathComponent(target))) != nil {
                track.cleanedFileName = target
            } else {
                track.cleanedFileName = nil
            }
        }
        project.deletedTracks.removeAll { $0.id == id }
        project.placeRecovered(track, in: slot)
        refreshDurations(&project)
        return slot
    }

    /// Erases a deleted track's audio for good.
    public func deleteTrackPermanently(_ project: inout Project, id: UUID) {
        guard let entry = project.deletedTracks.first(where: { $0.id == id }) else { return }
        let dir = directory(for: project.id)
        for name in [entry.track.audioFileName, entry.track.cleanedFileName].compactMap({ $0 }) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
        project.deletedTracks.removeAll { $0.id == id }
    }

    /// "New Project", "New Project 2", ... like Voice Memos' "New Recording N".
    public func nextDefaultName() -> String {
        let names = Set(loadEverything().filter { $0.deletedAt == nil }.map(\.name))
        let base = "New Project"
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Derived data

    /// Re-reads track lengths from disk and updates per-track and project durations.
    public func refreshDurations(_ project: inout Project) {
        for i in project.tracks.indices {
            if let name = project.tracks[i].audioFileName,
               let reader = try? CAFReader(url: fileURL(name, in: project.id)) {
                project.tracks[i].durationSeconds = reader.durationSeconds
            } else {
                project.tracks[i].durationSeconds = 0
            }
        }
        project.durationSeconds = project.tracks.map(\.durationSeconds).max() ?? 0
    }

    /// Removes leftover temp files from an interrupted splice. The scratch
    /// recording is kept: `pendingRecording(project:)` hands it back for recovery.
    public func cleanTemporaryFiles(project id: UUID) {
        let dir = directory(for: id)
        guard let entries = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in entries where name.contains(".splice-") {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: Crash recovery

    public func pendingRecordingURL(project id: UUID) -> URL {
        fileURL(".recording.json", in: id)
    }

    /// Written when recording starts so a take survives a crash or a kill
    /// before the splice runs.
    public func savePendingRecording(_ pending: PendingRecording, project id: UUID) throws {
        try encoder.encode(pending).write(to: pendingRecordingURL(project: id), options: .atomic)
    }

    public func pendingRecording(project id: UUID) -> PendingRecording? {
        guard let data = try? Data(contentsOf: pendingRecordingURL(project: id)),
              let pending = try? decoder.decode(PendingRecording.self, from: data),
              fm.fileExists(atPath: recordingTempURL(project: id).path)
        else { return nil }
        return pending
    }

    public func clearPendingRecording(project id: UUID) {
        try? fm.removeItem(at: pendingRecordingURL(project: id))
        try? fm.removeItem(at: recordingTempURL(project: id))
    }
}

/// Everything needed to splice a scratch recording into its track later.
public struct PendingRecording: Codable, Equatable, Sendable {
    public var trackIndex: Int
    /// Timeline frame where recording started.
    public var insertFrame: Int64
    /// Frames of the scratch file to skip (latency + pre-roll), when known.
    public var skipFrames: Int64
    public var inputGainDB: Double
    public var route: AudioRouteKind

    public init(trackIndex: Int, insertFrame: Int64, skipFrames: Int64, inputGainDB: Double, route: AudioRouteKind) {
        self.trackIndex = trackIndex
        self.insertFrame = insertFrame
        self.skipFrames = skipFrames
        self.inputGainDB = inputGainDB
        self.route = route
    }
}
