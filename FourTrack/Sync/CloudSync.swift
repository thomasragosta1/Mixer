import CloudKit
import Foundation
import Observation
import FourTrackCore

/// Keeps projects in step across a person's devices through their own iCloud
/// (the private CloudKit database, which only they can read; the developer
/// has no access). Built on `CKSyncEngine`, which schedules the network work,
/// retries and resumes after the app is killed.
///
/// In iCloud, each project is one small record (project.json and a manifest
/// of its audio files) and each audio file is its own immutable record, so a
/// slider tweak sends a few kilobytes and a new take sends only that take.
/// Conflicts are settled per project: the most recently edited version wins.
/// A project that's open isn't changed underneath the person; updates for it
/// wait until it's closed.
@Observable
@MainActor
final class CloudSync {
    static let shared = CloudSync()

    enum Status: Equatable {
        case off
        case checking
        case noAccount
        case syncing
        case upToDate
        case storageFull
        case failed(String)

        var text: String {
            switch self {
            case .off: "Off"
            case .checking: "Checking iCloud…"
            case .noAccount: "Sign in to iCloud in Settings to sync."
            case .syncing: "Syncing…"
            case .upToDate: "Up to date"
            case .storageFull: "Your iCloud storage is full. Projects stay on this iPhone."
            case .failed(let message): message
            }
        }
    }

    private(set) var status: Status = .off

    /// Posted when projects on disk changed because of another device.
    static let projectsChanged = Notification.Name("CloudSyncProjectsChanged")

    @ObservationIgnored private var store: ProjectStore?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var disk = SyncDisk()
    @ObservationIgnored private var openProject: UUID?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// project.json hash per project record being sent.
    @ObservationIgnored private var sentHashes: [String: UInt64] = [:]
    @ObservationIgnored private var staging: Set<String> = []

    private let zoneID = CKRecordZone.ID(zoneName: SyncNames.zoneName)

    // MARK: Folders

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CloudSync", isDirectory: true)
    }
    private static var diskURL: URL { folder.appendingPathComponent("ledger.json") }
    private static var engineStateURL: URL { folder.appendingPathComponent("engine.json") }
    private static var outgoingFolder: URL { folder.appendingPathComponent("Outgoing", isDirectory: true) }
    private static var incomingFolder: URL { folder.appendingPathComponent("Incoming", isDirectory: true) }

    // MARK: Lifecycle

    /// False in a build that was signed without iCloud (the switch is hidden;
    /// touching CloudKit there would crash).
    static var isAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FTCloudSyncAvailable") as? Bool ?? true
    }

    /// Called once at launch with the app's project store.
    func configure(store: ProjectStore, enabled: Bool) {
        self.store = store
        store.onChange = { id in
            Task { @MainActor in CloudSync.shared.localChange(id) }
        }
        if enabled { Task { await start() } }
    }

    func setEnabled(_ on: Bool) {
        if on {
            Task { await start() }
        } else {
            stop()
            status = .off
        }
    }

    private func start() async {
        guard engine == nil, store != nil, Self.isAvailable, !DemoContent.isEnabled else { return }
        status = .checking
        let container = CKContainer.default()
        let account = (try? await container.accountStatus()) ?? .couldNotDetermine
        guard account == .available else {
            status = .noAccount
            return
        }
        for dir in [Self.folder, Self.outgoingFolder, Self.incomingFolder] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        disk = Self.loadDisk()
        Self.purgeOldBackups()
        var config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: Self.loadEngineState(),
            delegate: self
        )
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        if !disk.zoneCreated {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        status = .syncing
        scanAll()
        for id in disk.incoming.keys { tryApplyIncoming(id) }
        Task { try? await engine.fetchChanges() }
    }

    private func stop() {
        engine = nil
        scanTask?.cancel()
    }

    /// App came to the front: pick up other devices' changes.
    func appBecameActive() {
        guard let engine else { return }
        Task {
            try? await engine.fetchChanges()
            scanAll()
        }
    }

    /// App going to the background: send what's waiting.
    func appWillResignActive() {
        guard let engine else { return }
        scanAll()
        Task { try? await engine.sendChanges() }
    }

    func projectOpened(_ id: UUID) {
        openProject = id
        guard let engine else { return }
        // Bring it up to date before editing starts, where possible.
        Task { try? await engine.fetchChanges() }
    }

    func projectClosed(_ id: UUID) {
        if openProject == id { openProject = nil }
        guard engine != nil else { return }
        resolveIncomingAfterLocalEdits(id)
        tryApplyIncoming(id)
    }

    // MARK: Local changes → iCloud

    private func localChange(_ id: UUID) {
        guard engine != nil else { return }
        // Saves come in bursts while editing; settle first.
        scanTask?.cancel()
        scanTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            scanAll()
        }
    }

    private func scanAll() {
        guard engine != nil, let store else { return }
        let local = Set(store.allProjectIDs())
        let missing = disk.ledger.projects.keys.filter { !local.contains($0) && disk.incoming[$0] == nil }
        // Several synced projects vanishing at once looks like a storage problem,
        // not the person deleting them: never pass that on to iCloud.
        let suspicious = missing.count >= 3 && missing.count * 2 > disk.ledger.projects.count
        for id in local { scanProject(id) }
        deletionsPaused = suspicious
        if !suspicious {
            for id in missing { deleteRemote(id) }
        }
        saveDisk()
        updateStatus()
    }

    private func scanProject(_ id: UUID) {
        guard let engine, let store else { return }
        // An update from another device is waiting to be applied: don't send over it.
        if disk.incoming[id] != nil { return }
        guard let data = store.metadataData(for: id) else { return }
        var state = disk.ledger.projects[id] ?? ProjectSyncState()
        let files = store.syncableFiles(in: id)
        var changed = false

        // Uploads overtaken by newer edits (or a deleted file) are dropped.
        for (name, out) in disk.ledger.outgoing where out.projectID == id && files[out.fileName] != out.fingerprint {
            disk.ledger.outgoing[name] = nil
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
            removeStaged(name)
            changed = true
        }
        let uploading = Dictionary(disk.ledger.outgoing.values.filter { $0.projectID == id }.map { ($0.fileName, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })
        let plan = SyncPlanner.outgoing(local: files, synced: state.files, uploading: uploading)
        for name in plan.uploads {
            guard let fingerprint = files[name] else { continue }
            let out = OutgoingFile(projectID: id, fileName: name, fingerprint: fingerprint, remoteID: UUID().uuidString.lowercased())
            disk.ledger.outgoing[out.recordName] = out
            changed = true
        }
        for remoteID in plan.retired {
            engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(SyncNames.audioRecordName(project: id, remoteID: remoteID)))])
            state.files = state.files.filter { $0.value.remoteID != remoteID }
            changed = true
        }
        disk.ledger.projects[id] = state

        // Every upload staged (compressed) and queued.
        let pendingSaves = Set(engine.state.pendingRecordZoneChanges.compactMap { change -> String? in
            if case .saveRecord(let rid) = change { return rid.recordName }
            return nil
        })
        for (name, out) in disk.ledger.outgoing where out.projectID == id {
            if out.staged, stagedURL(name) != nil {
                if !pendingSaves.contains(name) { engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))]) }
            } else {
                stage(out)
            }
        }

        let projectRecord = SyncNames.projectRecordName(id)
        if changed || SyncPlanner.hash(data) != state.metadataHash, !pendingSaves.contains(projectRecord) {
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(projectRecord))])
        }
    }

    private func deleteRemote(_ id: UUID) {
        guard let engine else { return }
        var deletes: [CKSyncEngine.PendingRecordZoneChange] = [.deleteRecord(recordID(SyncNames.projectRecordName(id)))]
        for file in (disk.ledger.projects[id]?.files ?? [:]).values {
            deletes.append(.deleteRecord(recordID(SyncNames.audioRecordName(project: id, remoteID: file.remoteID))))
        }
        for (name, out) in disk.ledger.outgoing where out.projectID == id {
            engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
            removeStaged(name)
        }
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID(SyncNames.projectRecordName(id)))])
        engine.state.add(pendingRecordZoneChanges: deletes)
        disk.ledger.forget(id)
    }

    /// Compresses a file for upload off the main thread, then queues it.
    private func stage(_ out: OutgoingFile) {
        let name = out.recordName
        guard let store, !staging.contains(name) else { return }
        staging.insert(name)
        let source = store.fileURL(out.fileName, in: out.projectID)
        let base = Self.outgoingFolder.appendingPathComponent(name)
        Task {
            let ok = await Task.detached(priority: .utility) { () -> Bool in
                (try? SyncAudio.stage(source, as: base)) != nil
            }.value
            staging.remove(name)
            guard var current = disk.ledger.outgoing[name], current.fingerprint == out.fingerprint else {
                removeStaged(name)
                return
            }
            if ok {
                current.staged = true
                disk.ledger.outgoing[name] = current
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
            } else {
                // The file changed or vanished while compressing; the next scan sorts it out.
                disk.ledger.outgoing[name] = nil
            }
            saveDisk()
        }
    }

    private func stagedURL(_ recordName: String) -> URL? {
        for ext in ["m4a", "caf"] {
            let url = Self.outgoingFolder.appendingPathComponent(recordName).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func removeStaged(_ recordName: String) {
        for ext in ["m4a", "caf", "json"] {
            try? FileManager.default.removeItem(at: Self.outgoingFolder.appendingPathComponent(recordName).appendingPathExtension(ext))
        }
    }

    /// Builds the record for a pending save, or nil if it can't be sent now.
    private func record(for id: CKRecord.ID) -> CKRecord? {
        guard let store else { return nil }
        let name = id.recordName
        let record = existingRecord(name) ?? CKRecord(recordType: UUID(uuidString: name) != nil ? SyncNames.projectType : SyncNames.audioType, recordID: id)
        if let projectID = UUID(uuidString: name) {
            guard let data = store.metadataData(for: projectID), let project = store.decodeProject(data) else { return nil }
            let json = Self.outgoingFolder.appendingPathComponent(name).appendingPathExtension("json")
            guard (try? data.write(to: json, options: .atomic)) != nil else { return nil }
            record["json"] = CKAsset(fileURL: json)
            record["files"] = SyncNames.encodeManifest(disk.ledger.manifest(for: projectID)) as CKRecordValue
            record["updatedAt"] = project.updatedAt as CKRecordValue
            sentHashes[name] = SyncPlanner.hash(data)
        } else {
            guard let out = disk.ledger.outgoing[name], let url = stagedURL(name) else { return nil }
            record["audio"] = CKAsset(fileURL: url)
            record["codec"] = (url.pathExtension == "m4a" ? "alac" : "caf") as CKRecordValue
            record["project"] = out.projectID.uuidString as CKRecordValue
        }
        return record
    }

    // MARK: iCloud → this device

    private func received(_ record: CKRecord) async {
        remember(record)
        if record.recordType == SyncNames.audioType {
            await receivedAudio(record)
        } else if record.recordType == SyncNames.projectType {
            receivedProject(record)
        }
    }

    private func receivedAudio(_ record: CKRecord) async {
        let name = record.recordID.recordName
        guard let projectID = SyncNames.project(ofAudioRecord: name),
              let asset = record["audio"] as? CKAsset, let url = asset.fileURL else { return }
        // Our own upload coming back.
        if disk.ledger.outgoing[name] != nil || disk.ledger.projects[projectID]?.files.values.contains(where: { SyncNames.audioRecordName(project: projectID, remoteID: $0.remoteID) == name }) == true { return }
        let ext = (record["codec"] as? String) == "caf" ? "caf" : "m4a"
        let copy = Self.incomingFolder.appendingPathComponent(name + ".download").appendingPathExtension(ext)
        let target = incomingURL(name)
        try? FileManager.default.removeItem(at: copy)
        // The asset file only lives for this callback: copy it now, convert after.
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
        let ok = await Task.detached(priority: .utility) { () -> Bool in
            defer { try? FileManager.default.removeItem(at: copy) }
            return (try? SyncAudio.restore(copy, to: target)) != nil
        }.value
        if ok { tryApplyIncoming(projectID) }
    }

    private func receivedProject(_ record: CKRecord) {
        guard let store, let id = UUID(uuidString: record.recordID.recordName),
              let asset = record["json"] as? CKAsset, let url = asset.fileURL,
              let data = try? Data(contentsOf: url), let remote = store.decodeProject(data) else { return }
        let manifest = SyncNames.decodeManifest(record["files"] as? [String] ?? [])
        let state = disk.ledger.projects[id]
        let remoteHash = SyncPlanner.hash(data)
        // Our own save coming back.
        if state?.metadataHash == remoteHash, manifest == disk.ledger.manifest(for: id) { return }
        // A project already on this device is only replaced by a strictly newer
        // edit from another device. Anything else (our own upload echoing back,
        // an older copy) leaves this device's version alone, and it gets sent.
        if let localData = store.metadataData(for: id), let local = store.decodeProject(localData),
           remote.updatedAt <= local.updatedAt {
            scanProject(id)
            return
        }
        disk.incoming[id] = IncomingProject(json: data, manifest: manifest, updatedAt: remote.updatedAt)
        saveDisk()
        tryApplyIncoming(id)
    }

    /// After a project closes: if it was edited after the waiting update was
    /// made elsewhere, the edits win and the update is dropped.
    private func resolveIncomingAfterLocalEdits(_ id: UUID) {
        guard let store, let incoming = disk.incoming[id], let localData = store.metadataData(for: id),
              let local = store.decodeProject(localData), local.updatedAt >= incoming.updatedAt else { return }
        disk.incoming[id] = nil
        saveDisk()
        scanProject(id)
    }

    /// Applies a waiting update once all its audio has arrived (and the
    /// project isn't open).
    private func tryApplyIncoming(_ id: UUID) {
        guard let store, let incoming = disk.incoming[id], openProject != id else { return }
        if incoming.deleted {
            // Deleted on another device: kept aside for a while, not erased.
            Self.backUp(project: id, files: nil, store: store)
            store.removeSynced(id: id)
            disk.ledger.forget(id)
            disk.incoming[id] = nil
            saveDisk()
            NotificationCenter.default.post(name: Self.projectsChanged, object: nil)
            return
        }
        let state = disk.ledger.projects[id] ?? ProjectSyncState()
        let plan = SyncPlanner.incoming(remote: incoming.manifest, synced: state.files, local: store.syncableFiles(in: id))
        for (_, remoteID) in plan.downloads {
            guard FileManager.default.fileExists(atPath: incomingURL(SyncNames.audioRecordName(project: id, remoteID: remoteID)).path) else { return }
        }
        let dir = store.directory(for: id)
        // Only files this device knows were already in iCloud are removed; audio
        // that never made it up is left alone.
        let removals = plan.removals.filter { state.files[$0] != nil }
        // Whatever gets replaced or removed is copied aside first.
        if store.metadataData(for: id) != nil {
            Self.backUp(project: id, files: Array(plan.downloads.keys) + removals, store: store)
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (fileName, remoteID) in plan.downloads {
                let source = incomingURL(SyncNames.audioRecordName(project: id, remoteID: remoteID))
                try AtomicFile.replace(dir.appendingPathComponent(fileName), with: source)
                // The waveform cache is rebuilt from the new audio.
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName.replacingOccurrences(of: ".caf", with: ".peaks")))
            }
            for fileName in removals {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName.replacingOccurrences(of: ".caf", with: ".peaks")))
            }
            try store.replaceMetadata(incoming.json, for: id)
        } catch {
            status = .failed("A project from iCloud couldn't be saved. \(error.localizedDescription)")
            return
        }
        let local = store.syncableFiles(in: id)
        var files: [String: SyncedFile] = [:]
        for (fileName, remoteID) in incoming.manifest {
            if let fingerprint = local[fileName] { files[fileName] = SyncedFile(fingerprint: fingerprint, remoteID: remoteID) }
        }
        disk.ledger.projects[id] = ProjectSyncState(metadataHash: SyncPlanner.hash(incoming.json), files: files)
        disk.incoming[id] = nil
        saveDisk()
        NotificationCenter.default.post(name: Self.projectsChanged, object: nil)
    }

    @ObservationIgnored private var fetchingMissing = false

    /// Audio a waiting update needs that hasn't come through the change feed
    /// (fetched directly). Audio that no longer exists in iCloud is dropped
    /// from the update so it can't wait forever.
    private func fetchMissingAudio() {
        guard engine != nil, let store, !fetchingMissing else { return }
        var wanted: [CKRecord.ID] = []
        for (id, incoming) in disk.incoming where !incoming.deleted {
            let state = disk.ledger.projects[id] ?? ProjectSyncState()
            let plan = SyncPlanner.incoming(remote: incoming.manifest, synced: state.files, local: store.syncableFiles(in: id))
            for remoteID in plan.downloads.values {
                let name = SyncNames.audioRecordName(project: id, remoteID: remoteID)
                if !FileManager.default.fileExists(atPath: incomingURL(name).path) { wanted.append(recordID(name)) }
            }
        }
        guard !wanted.isEmpty else { return }
        fetchingMissing = true
        Task {
            defer { fetchingMissing = false }
            guard let results = try? await CKContainer.default().privateCloudDatabase.records(for: wanted) else { return }
            for (id, result) in results {
                switch result {
                case .success(let record):
                    await received(record)
                case .failure(let error):
                    if (error as? CKError)?.code == .unknownItem { dropMissingAudio(id.recordName) }
                }
            }
            saveDisk()
        }
    }

    private func dropMissingAudio(_ recordName: String) {
        guard let projectID = SyncNames.project(ofAudioRecord: recordName),
              let remoteID = SyncNames.remoteID(ofAudioRecord: recordName),
              var incoming = disk.incoming[projectID] else { return }
        incoming.manifest = incoming.manifest.filter { $0.value != remoteID }
        disk.incoming[projectID] = incoming
        tryApplyIncoming(projectID)
    }

    // MARK: Safety copies

    /// Copies of everything sync replaced or removed, kept for 30 days in
    /// Application Support/SyncBackups/<date>/<project>/.
    private static var backupFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncBackups", isDirectory: true)
    }

    /// `files` nil copies the whole project folder; otherwise project.json and those files.
    private static func backUp(project id: UUID, files: [String]?, store: ProjectStore) {
        let fm = FileManager.default
        let source = store.directory(for: id)
        guard fm.fileExists(atPath: source.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = backupFolder.appendingPathComponent(stamp, isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if files == nil {
            try? fm.copyItem(at: source, to: target)
            return
        }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["project.json"] + (files ?? []) {
            let from = source.appendingPathComponent(name)
            if fm.fileExists(atPath: from.path) { try? fm.copyItem(at: from, to: target.appendingPathComponent(name)) }
        }
    }

    private static func purgeOldBackups() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: backupFolder, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            if created < cutoff { try? fm.removeItem(at: entry) }
        }
    }

    private func incomingURL(_ recordName: String) -> URL {
        Self.incomingFolder.appendingPathComponent(recordName).appendingPathExtension("caf")
    }

    private func receivedDeletion(_ id: CKRecord.ID, type: CKRecord.RecordType) {
        disk.ledger.systemFields[id.recordName] = nil
        guard type == SyncNames.projectType, let projectID = UUID(uuidString: id.recordName) else { return }
        disk.incoming[projectID] = IncomingProject(json: Data(), manifest: [:], updatedAt: .distantFuture, deleted: true)
        saveDisk()
        tryApplyIncoming(projectID)
    }

    // MARK: Records' system fields (change tags)

    private func recordID(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name, zoneID: zoneID) }

    private func remember(_ record: CKRecord) {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        disk.ledger.systemFields[record.recordID.recordName] = archiver.encodedData
    }

    private func existingRecord(_ name: String) -> CKRecord? {
        guard let data = disk.ledger.systemFields[name],
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }

    // MARK: Events

    fileprivate func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) async {
        guard engine === self.engine else { return }
        switch event {
        case .stateUpdate(let update):
            Self.saveEngineState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                scanAll()
            case .signOut, .switchAccounts:
                // A different (or no) iCloud account: start over, keeping everything on this device.
                stop()
                resetSyncState()
                status = .noAccount
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == zoneID {
                // The person deleted this app's iCloud data (Settings → iCloud). Respect
                // that: stop syncing rather than upload everything again.
                stop()
                resetSyncState()
                AppSettings.shared.iCloudSync = false
                status = .failed("Four-Track's iCloud data was deleted, so sync was turned off. Your projects are still on this iPhone.")
                return
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                await received(modification.record)
            }
            for deletion in changes.deletions {
                receivedDeletion(deletion.recordID, type: deletion.recordType)
            }
            saveDisk()

        case .sentDatabaseChanges(let changes):
            if changes.savedZones.contains(where: { $0.zoneID == zoneID }) {
                disk.zoneCreated = true
                saveDisk()
            }

        case .sentRecordZoneChanges(let changes):
            sent(changes, engine: engine)

        case .didFetchChanges:
            fetchMissingAudio()
            updateStatus()

        case .didSendChanges:
            updateStatus()

        case .willFetchChanges, .willSendChanges:
            if status != .storageFull { status = .syncing }

        default:
            break
        }
    }

    private func sent(_ changes: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) {
        for record in changes.savedRecords {
            remember(record)
            let name = record.recordID.recordName
            if let id = UUID(uuidString: name) {
                var state = disk.ledger.projects[id] ?? ProjectSyncState()
                state.metadataHash = sentHashes.removeValue(forKey: name) ?? state.metadataHash
                disk.ledger.projects[id] = state
                removeStaged(name)
            } else {
                disk.ledger.confirmUpload(recordName: name)
                removeStaged(name)
            }
        }
        for deleted in changes.deletedRecordIDs {
            disk.ledger.systemFields[deleted.recordName] = nil
        }
        for failure in changes.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                remember(server)
                if server.recordType == SyncNames.projectType {
                    // Edited on two devices: the newer one wins.
                    receivedProject(server)
                    if let pid = UUID(uuidString: id.recordName), disk.incoming[pid] == nil {
                        engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                    }
                } else {
                    // Audio records are immutable; the server copy is the same content.
                    disk.ledger.confirmUpload(recordName: id.recordName)
                    removeStaged(id.recordName)
                }
            case .zoneNotFound, .userDeletedZone:
                disk.zoneCreated = false
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .unknownItem:
                disk.ledger.systemFields[id.recordName] = nil
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            case .quotaExceeded:
                status = .storageFull
            default:
                break
            }
        }
        saveDisk()
        updateStatus()
    }

    @ObservationIgnored private var deletionsPaused = false

    private func updateStatus() {
        guard let engine else { return }
        if deletionsPaused {
            status = .failed("Some projects couldn't be read on this iPhone, so sync paused deletions to keep iCloud's copies safe.")
            return
        }
        if status == .storageFull || status == .checking { return }
        let busy = !engine.state.pendingRecordZoneChanges.isEmpty || !staging.isEmpty || !disk.incoming.isEmpty
        status = busy ? .syncing : .upToDate
    }

    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext, engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === self.engine else { return nil }
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        var records: [CKRecord.ID: CKRecord] = [:]
        var unsendable: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case .saveRecord(let id) = change else { continue }
            if let record = record(for: id) {
                records[id] = record
            } else if UUID(uuidString: id.recordName) == nil, disk.ledger.outgoing[id.recordName] == nil {
                // An upload that's no longer wanted.
                unsendable.append(change)
            }
        }
        engine.state.remove(pendingRecordZoneChanges: unsendable)
        let sendable = pending.filter { change in
            if case .saveRecord(let id) = change { return records[id] != nil }
            return true
        }
        guard !sendable.isEmpty else { return nil }
        let prepared = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: sendable) { prepared[$0] }
    }

    // MARK: Persistence

    private func resetSyncState() {
        disk = SyncDisk()
        try? FileManager.default.removeItem(at: Self.folder)
    }

    private func saveDisk() {
        guard let data = try? JSONEncoder().encode(disk) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.diskURL, options: .atomic)
    }

    private static func loadDisk() -> SyncDisk {
        guard let data = try? Data(contentsOf: diskURL), let disk = try? JSONDecoder().decode(SyncDisk.self, from: data) else { return SyncDisk() }
        return disk
    }

    private static func saveEngineState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: engineStateURL, options: .atomic)
    }

    private static func loadEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: engineStateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }
}

/// An update from another device, kept on disk until its audio has arrived.
struct IncomingProject: Codable {
    var json: Data
    var manifest: [String: String]
    var updatedAt: Date
    var deleted = false
}

struct SyncDisk: Codable {
    var ledger = SyncLedger()
    var incoming: [UUID: IncomingProject] = [:]
    var zoneCreated = false
}

extension CloudSync: CKSyncEngineDelegate {
    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, engine: syncEngine)
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await nextBatch(context, engine: syncEngine)
    }
}
