import Foundation
import Observation
import FourTrackCore

/// The Voice Memos-style list of projects.
@Observable
@MainActor
final class ProjectsViewModel {
    private(set) var projects: [Project] = []
    private(set) var binned: [Project] = []
    var binCount: Int { binned.count }
    var errorMessage: String?
    let store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
        reload()
    }

    static func makeStore() -> ProjectStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if DemoContent.isEnabled, let demo = try? DemoContent.makeStore(root: support.appendingPathComponent("DemoProjects", isDirectory: true)) {
            return demo
        }
        let root = support.appendingPathComponent("Projects", isDirectory: true)
        do {
            return try ProjectStore(rootURL: root)
        } catch {
            // Application Support is always creatable in practice; fall back to temp so the app still runs.
            let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("Projects", isDirectory: true)
            return try! ProjectStore(rootURL: fallback)
        }
    }

    func reload() {
        projects = store.loadAll()
        binned = store.loadBin()
    }

    var nextDefaultName: String { store.nextDefaultName() }

    func createProject(named name: String? = nil, mode: ProjectMode = .simple) -> Project? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let project = try store.create(name: (trimmed?.isEmpty ?? true) ? nil : trimmed, mode: mode)
            reload()
            return project
        } catch {
            errorMessage = "Couldn't create a project. \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Importing audio

    /// A recording shared in (Voice Memos → Share → Four-Track) or picked with
    /// Import Audio, waiting for "New Project or which project?".
    var pendingImport: URL?
    private(set) var isImporting = false

    /// Projects a recording can go into: any with a lane free.
    var projectsWithRoom: [Project] { projects.filter { $0.freeSlotForRecovery() != nil } }

    /// Converts the recording into a new track. With no project, it starts a
    /// new one named after the recording. Returns the project to open.
    func importPending(into existing: Project?) async -> UUID? {
        guard let source = pendingImport else { return nil }
        pendingImport = nil
        isImporting = true
        defer {
            isImporting = false
            Self.discardInboxCopy(source)
        }
        let title = Self.title(for: source)
        var project: Project
        if let existing {
            guard let fresh = try? store.load(id: existing.id) else {
                errorMessage = "Couldn't open \(existing.name)."
                return nil
            }
            project = fresh
        } else {
            guard let created = createProject(named: title, mode: .simple) else { return nil }
            project = created
        }
        guard let slot = project.freeSlotForRecovery() else {
            errorMessage = "\(project.name) already has four tracks. Delete one, or add the recording to a new project."
            return nil
        }
        let destination = store.audioURL(project: project.id, track: slot)
        let peaksURL = store.peaksURL(project: project.id, track: slot)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
            do {
                try AudioImporter.importAudio(from: source, to: destination)
                let peaks = try PeakGenerator.peaks(ofFileAt: destination)
                try? PeakGenerator.write(peaks, to: peaksURL)
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success:
            var track = Track(index: slot, name: String(title.prefix(30)))
            track.audioFileName = ProjectStore.audioFileName(track: slot)
            project.placeRecovered(track, in: slot)
            store.refreshDurations(&project)
            project.updatedAt = Date()
            do {
                try store.save(project)
            } catch {
                errorMessage = "Couldn't save \(project.name). \(error.localizedDescription)"
                return nil
            }
            reload()
            return project.id
        case .failure(let error):
            if existing == nil { try? store.delete(id: project.id) }
            reload()
            errorMessage = "Couldn't import \u{201C}\(title)\u{201D}. \(error.localizedDescription)"
            return nil
        }
    }

    func cancelImport() {
        if let source = pendingImport { Self.discardInboxCopy(source) }
        pendingImport = nil
    }

    /// "New Recording 12.m4a" → "New Recording 12".
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Imported Audio" : name
    }

    /// Files shared into the app land in Documents/Inbox; once imported, the
    /// copy is no longer needed.
    private static func discardInboxCopy(_ url: URL) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(documents) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a project to Recently Deleted. Nothing is lost until it's deleted from there.
    func delete(_ project: Project) {
        do {
            try store.moveToBin(id: project.id)
        } catch {
            errorMessage = "Couldn't delete \(project.name). \(error.localizedDescription)"
        }
        reload()
    }

    func recover(_ project: Project) {
        do {
            try store.restore(id: project.id)
        } catch {
            errorMessage = "Couldn't recover \(project.name). \(error.localizedDescription)"
        }
        reload()
    }

    /// Permanent. Only offered inside Recently Deleted, behind a confirmation.
    func deletePermanently(_ projects: [Project]) {
        for project in projects {
            do {
                try store.delete(id: project.id)
            } catch {
                errorMessage = "Couldn't delete \(project.name). \(error.localizedDescription)"
            }
        }
        reload()
    }

    func rename(_ project: Project, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var loaded = try? store.load(id: project.id) else { return }
        loaded.name = trimmed
        loaded.updatedAt = Date()
        try? store.save(loaded)
        reload()
    }
}

enum TimeFormat {
    /// "0:42", "3:07", "1:02:03" like Voice Memos.
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "0:42.37" for the transport readout.
    static func precise(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let total = Int(clamped.rounded(.down))
        let hundredths = Int((clamped - Double(total)) * 100)
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d.%02d", m, s, hundredths)
    }
}
