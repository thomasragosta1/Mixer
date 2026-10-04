import Foundation
import FourTrackCore

/// Undo / redo for a project, with a long history (1,000 steps).
///
/// Each step stores the whole project as it was before a change (projects are
/// small value types). Steps that rewrite audio (recording, drum renders, kit
/// and pad changes, deleting tracks) also keep the affected audio files as they
/// were, as clones in the project's `.undo` folder. On iOS (APFS) a clone
/// shares storage with the original until the original is rewritten, so only
/// audio that actually changed takes space. Slider moves within a second of
/// each other on the same control merge into one step.
final class UndoHistory {
    struct FileSnapshot {
        let folder: URL
        /// Every file name the snapshot covers, and which of them existed.
        let names: Set<String>
        let present: Set<String>
    }

    struct Step {
        var project: Project
        var label: String
        var files: FileSnapshot?
    }

    static let limit = 1_000
    static let mergeWindow: TimeInterval = 1.0

    private let store: ProjectStore
    private let projectID: UUID
    private let fm = FileManager.default
    private(set) var undoSteps: [Step] = []
    private(set) var redoSteps: [Step] = []
    private var lastKey: String?
    private var lastTime = Date.distantPast

    init(store: ProjectStore, projectID: UUID) {
        self.store = store
        self.projectID = projectID
        // Leftovers from a session that ended without closing.
        try? fm.removeItem(at: folder)
    }

    var folder: URL { store.directory(for: projectID).appendingPathComponent(".undo", isDirectory: true) }

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }
    var undoLabel: String? { undoSteps.last?.label }
    var redoLabel: String? { redoSteps.last?.label }

    /// Records the state before a change. `key` merges rapid repeats of the same
    /// edit (a slider drag) into one step; `audio` also keeps the audio files.
    func checkpoint(_ project: Project, label: String, key: String? = nil, audio: Bool = false) {
        let now = Date()
        if !audio, let key, key == lastKey, now.timeIntervalSince(lastTime) < Self.mergeWindow {
            lastTime = now
            return
        }
        lastKey = audio ? nil : key
        lastTime = now
        undoSteps.append(Step(project: project, label: label, files: audio ? snapshotFiles(of: project) : nil))
        discard(&redoSteps)
        if undoSteps.count > Self.limit {
            let dropped = undoSteps.removeFirst()
            remove(dropped.files)
        }
    }

    /// Takes back the last step. `current` becomes a redo step. Returns the project to restore.
    func undo(current: Project) -> Step? {
        guard let step = undoSteps.popLast() else { return nil }
        lastKey = nil
        redoSteps.append(Step(project: current, label: step.label, files: step.files == nil ? nil : snapshotFiles(of: current, also: step.files?.names ?? [])))
        restore(step.files)
        return step
    }

    func redo(current: Project) -> Step? {
        guard let step = redoSteps.popLast() else { return nil }
        lastKey = nil
        undoSteps.append(Step(project: current, label: step.label, files: step.files == nil ? nil : snapshotFiles(of: current, also: step.files?.names ?? [])))
        restore(step.files)
        return step
    }

    /// Deletes the history and its audio copies (when the project closes).
    func clear() {
        undoSteps.removeAll()
        redoSteps.removeAll()
        try? fm.removeItem(at: folder)
    }

    // MARK: Files

    /// Every audio-related file a project state depends on: the four tracks'
    /// takes, Cleanup renders and waveform caches (present or not), plus the
    /// audio of tracks in the project's Recently Deleted.
    private func fileNames(of project: Project) -> Set<String> {
        var names = Set<String>()
        for i in 0..<Project.trackCount {
            names.insert(ProjectStore.audioFileName(track: i))
            names.insert(ProjectStore.cleanedFileName(track: i))
            names.insert(ProjectStore.peaksFileName(track: i))
        }
        for t in project.tracks {
            if let n = t.audioFileName { names.insert(n) }
            if let n = t.cleanedFileName { names.insert(n) }
        }
        for d in project.deletedTracks {
            if let n = d.track.audioFileName { names.insert(n) }
            if let n = d.track.cleanedFileName { names.insert(n) }
        }
        return names
    }

    private func snapshotFiles(of project: Project, also extra: Set<String> = []) -> FileSnapshot? {
        let dir = store.directory(for: projectID)
        let snap = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fm.createDirectory(at: snap, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let names = fileNames(of: project).union(extra)
        var present = Set<String>()
        for name in names {
            let src = dir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            // copyItem clones on APFS: instant, and no extra space until the original changes.
            if (try? fm.copyItem(at: src, to: snap.appendingPathComponent(name))) != nil {
                present.insert(name)
            }
        }
        return FileSnapshot(folder: snap, names: names, present: present)
    }

    /// Puts the project folder's files back exactly as in the snapshot.
    private func restore(_ snapshot: FileSnapshot?) {
        guard let snapshot else { return }
        let dir = store.directory(for: projectID)
        for name in snapshot.names {
            let dest = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            if snapshot.present.contains(name) {
                try? fm.copyItem(at: snapshot.folder.appendingPathComponent(name), to: dest)
            }
        }
        remove(snapshot)
    }

    private func remove(_ snapshot: FileSnapshot?) {
        guard let snapshot else { return }
        try? fm.removeItem(at: snapshot.folder)
    }

    private func discard(_ steps: inout [Step]) {
        steps.forEach { remove($0.files) }
        steps.removeAll()
    }
}
