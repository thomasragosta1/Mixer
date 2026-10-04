import SwiftUI
import FourTrackCore

/// Home screen, Voice Memos style: a list of projects and a big record button
/// that starts a new project recording on Track 1.
struct ProjectsListView: View {
    @State private var model: ProjectsViewModel
    @State private var path: [Route] = []
    @State private var pendingDelete: Project?
    @State private var renaming: Project?
    @State private var draftName = ""
    @State private var showingSettings = false
    let settings: AppSettings

    enum Route: Hashable {
        case project(UUID, record: Bool)
    }

    init(store: ProjectStore, settings: AppSettings) {
        _model = State(wrappedValue: ProjectsViewModel(store: store))
        self.settings = settings
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                list
                Divider()
                RecordButton(isRecording: false) { newProject(record: true) }
                    .padding(.vertical, 14)
                    .accessibilityLabel("New recording")
                    .accessibilityHint("Creates a project and starts recording on Track 1")
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Four-Track")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newProject(record: false)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New project")
                    .accessibilityHint("Creates an empty project without recording")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case let .project(id, record):
                    if let project = model.projects.first(where: { $0.id == id }) ?? (try? model.store.load(id: id)) {
                        ProjectView(project: project, store: model.store, startRecording: record) { deleted in
                            model.delete(deleted)
                        }
                    } else {
                        ContentUnavailableView("Project Not Found", systemImage: "questionmark.folder")
                    }
                }
            }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { model.reload() }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: nil, settings: settings)
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "Project")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { project in
                Button("Delete Project", role: .destructive) { model.delete(project) }
            } message: { _ in
                Text("All four tracks will be deleted. This can't be undone.")
            }
            .alert("Rename Project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let renaming { model.rename(renaming, to: draftName) }
                }
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.projects.isEmpty {
            ContentUnavailableView {
                Label("No Projects", systemImage: "waveform")
            } description: {
                Text("Tap the record button to start a song, or + to start an empty project. Each project has four tracks: record a part, then layer the next one over it.")
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(model.projects) { project in
                    ProjectRow(project: project)
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(.project(project.id, record: false)) }
                        .onLongPressGesture {
                            draftName = project.name
                            renaming = project
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = project
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Rename") {
                            draftName = project.name
                            renaming = project
                        }
                        .accessibilityAction(named: "Delete") { pendingDelete = project }
                }
            }
            .listStyle(.plain)
        }
    }

    private func newProject(record: Bool) {
        guard let project = model.createProject() else { return }
        path.append(.project(project.id, record: record))
    }
}

struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(project.createdAt, format: .dateTime.month(.abbreviated).day().year())
                Spacer()
                Text(TimeFormat.duration(project.durationSeconds))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
