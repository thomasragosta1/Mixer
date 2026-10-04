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

    func createProject(named name: String? = nil) -> Project? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let project = try store.create(name: (trimmed?.isEmpty ?? true) ? nil : trimmed)
            reload()
            return project
        } catch {
            errorMessage = "Couldn't create a project. \(error.localizedDescription)"
            return nil
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
