import Foundation

/// What iCloud sync knows about each project, so only real changes travel.
///
/// A project is one small record (its project.json plus a manifest of its
/// audio files) and one record per audio file. Audio records are immutable:
/// a file that changes gets a new remote ID and a new record, and the old one
/// is deleted. So editing a slider re-sends a few kilobytes, and re-recording
/// one track re-sends that track only.

/// Cheap change detection for a file on disk.
public struct FileFingerprint: Codable, Equatable, Sendable {
    public var size: Int64
    public var modified: Double

    public init(size: Int64, modified: Double) {
        self.size = size
        self.modified = modified
    }
}

/// An audio file as it was last confirmed in iCloud.
public struct SyncedFile: Codable, Equatable, Sendable {
    public var fingerprint: FileFingerprint
    public var remoteID: String

    public init(fingerprint: FileFingerprint, remoteID: String) {
        self.fingerprint = fingerprint
        self.remoteID = remoteID
    }
}

/// An audio file waiting to be uploaded under a new remote ID.
public struct OutgoingFile: Codable, Equatable, Sendable {
    public var projectID: UUID
    public var fileName: String
    public var fingerprint: FileFingerprint
    public var remoteID: String
    /// The compressed copy for upload has been written.
    public var staged: Bool

    public init(projectID: UUID, fileName: String, fingerprint: FileFingerprint, remoteID: String, staged: Bool = false) {
        self.projectID = projectID
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.remoteID = remoteID
        self.staged = staged
    }

    public var recordName: String { SyncNames.audioRecordName(project: projectID, remoteID: remoteID) }
}

public struct ProjectSyncState: Codable, Equatable, Sendable {
    /// Hash of the project.json last sent or received.
    public var metadataHash: UInt64?
    /// Audio confirmed in iCloud, by local file name.
    public var files: [String: SyncedFile] = [:]

    public init(metadataHash: UInt64? = nil, files: [String: SyncedFile] = [:]) {
        self.metadataHash = metadataHash
        self.files = files
    }
}

public struct SyncLedger: Codable, Equatable, Sendable {
    public var projects: [UUID: ProjectSyncState] = [:]
    /// Uploads in flight, by audio record name.
    public var outgoing: [String: OutgoingFile] = [:]
    /// CloudKit system fields (change tags) of the last known server records.
    public var systemFields: [String: Data] = [:]

    public init() {}

    /// The manifest a project record carries: every audio file and the remote
    /// ID holding its current content (confirmed or still uploading).
    public func manifest(for id: UUID) -> [String: String] {
        var m = (projects[id]?.files ?? [:]).mapValues(\.remoteID)
        for file in outgoing.values where file.projectID == id { m[file.fileName] = file.remoteID }
        return m
    }

    /// Records the end of an upload.
    public mutating func confirmUpload(recordName: String) {
        guard let file = outgoing.removeValue(forKey: recordName) else { return }
        var state = projects[file.projectID] ?? ProjectSyncState()
        state.files[file.fileName] = SyncedFile(fingerprint: file.fingerprint, remoteID: file.remoteID)
        projects[file.projectID] = state
    }

    /// Forgets a project (deleted here or in iCloud), with its pending uploads.
    public mutating func forget(_ id: UUID) {
        projects[id] = nil
        outgoing = outgoing.filter { $0.value.projectID != id }
        systemFields[SyncNames.projectRecordName(id)] = nil
    }
}

public enum SyncNames {
    public static let zoneName = "Projects"
    public static let projectType = "Project"
    public static let audioType = "AudioFile"

    public static func projectRecordName(_ id: UUID) -> String { id.uuidString }

    public static func audioRecordName(project: UUID, remoteID: String) -> String { "\(project.uuidString).\(remoteID)" }

    /// The project an audio record belongs to.
    public static func project(ofAudioRecord name: String) -> UUID? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        return UUID(uuidString: String(name[..<dot]))
    }

    public static func remoteID(ofAudioRecord name: String) -> String? {
        guard let dot = name.firstIndex(of: ".") else { return nil }
        return String(name[name.index(after: dot)...])
    }

    /// Audio worth syncing: the tracks, their Clean Up renders and binned
    /// tracks. Not scratch recordings, splice temps or waveform caches.
    public static func isSyncable(_ fileName: String) -> Bool {
        fileName.hasSuffix(".caf") && !fileName.hasPrefix(".") && !fileName.contains(".splice-") && !fileName.contains("/")
    }

    private static let separator: Character = "\u{1F}"

    public static func encodeManifest(_ manifest: [String: String]) -> [String] {
        manifest.sorted { $0.key < $1.key }.map { "\($0.key)\(separator)\($0.value)" }
    }

    public static func decodeManifest(_ entries: [String]) -> [String: String] {
        var m: [String: String] = [:]
        for entry in entries {
            let parts = entry.split(separator: separator, maxSplits: 1).map(String.init)
            guard parts.count == 2, isSyncable(parts[0]), !parts[1].isEmpty else { continue }
            m[parts[0]] = parts[1]
        }
        return m
    }
}

public enum SyncPlanner {
    /// What to upload and what to retire after local changes.
    public struct Outgoing: Equatable, Sendable {
        /// Files whose content isn't in iCloud yet.
        public var uploads: [String] = []
        /// Remote IDs no longer used by any file.
        public var retired: [String] = []
    }

    /// Compares the audio on disk with what iCloud has (or is receiving).
    public static func outgoing(local: [String: FileFingerprint], synced: [String: SyncedFile], uploading: [String: FileFingerprint]) -> Outgoing {
        var plan = Outgoing()
        for (name, fingerprint) in local.sorted(by: { $0.key < $1.key }) {
            if synced[name]?.fingerprint == fingerprint || uploading[name] == fingerprint { continue }
            plan.uploads.append(name)
        }
        for (name, file) in synced.sorted(by: { $0.key < $1.key }) where local[name] != file.fingerprint {
            plan.retired.append(file.remoteID)
        }
        return plan
    }

    /// What to do on this device to match a project's manifest from iCloud.
    public struct Incoming: Equatable, Sendable {
        /// File name → remote ID to download.
        public var downloads: [String: String] = [:]
        /// Local files the remote project no longer has.
        public var removals: [String] = []
    }

    public static func incoming(remote: [String: String], synced: [String: SyncedFile], local: [String: FileFingerprint]) -> Incoming {
        var plan = Incoming()
        for (name, remoteID) in remote {
            // Already have this exact content, unchanged since it was synced.
            if let s = synced[name], s.remoteID == remoteID, local[name] == s.fingerprint { continue }
            plan.downloads[name] = remoteID
        }
        plan.removals = local.keys.filter { remote[$0] == nil }.sorted()
        return plan
    }

    /// FNV-1a, for spotting changed project.json without a crypto dependency.
    public static func hash(_ data: Data) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in data {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }
}
