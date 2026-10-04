import SwiftUI
import UIKit
import FourTrackCore

/// Home screen, Voice Memos style: a list of projects and a big record button
/// that starts a new project recording on Track 1.
struct ProjectsListView: View {
    @State private var model: ProjectsViewModel
    @State private var path: [Route] = []
    @State private var renaming: Project?
    @State private var draftName = ""
    @State private var showingSettings = false
    @State private var namingNewProject = false
    let settings: AppSettings

    enum Route: Hashable {
        case project(UUID, record: Bool)
        case bin
    }

    init(store: ProjectStore, settings: AppSettings) {
        _model = State(wrappedValue: ProjectsViewModel(store: store))
        self.settings = settings
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                list
                    .overlay(alignment: .bottom) {
                        NewProjectButton {
                            withAnimation(.easeOut(duration: 0.2)) { namingNewProject = true }
                        }
                            .padding(.bottom, 14)
                    }
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
                case .bin:
                    BinView(model: model)
                }
            }
            .onChange(of: path) { _, newPath in
                if newPath.isEmpty { model.reload() }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: nil, settings: settings)
            }
            .overlay {
                if namingNewProject {
                    NewProjectBubble(defaultName: model.nextDefaultName) { name in
                        withAnimation(.easeOut(duration: 0.15)) { namingNewProject = false }
                        guard let name, let project = model.createProject(named: name) else { return }
                        path.append(.project(project.id, record: false))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                }
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
        if model.projects.isEmpty && model.binCount == 0 {
            ContentUnavailableView {
                Label("No Projects", systemImage: "waveform")
            } description: {
                Text("Tap the record button to start a song, or New Project to set one up first. Each project has four tracks: record a part, then layer the next one over it.")
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 60)
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
                        // Deleting only moves the project to the bin, so no confirmation here.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.delete(project)
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
                        .accessibilityAction(named: "Delete") { model.delete(project) }
                }
                if model.binCount > 0 {
                    Button {
                        path.append(.bin)
                    } label: {
                        HStack {
                            Label("Recently Deleted", systemImage: "trash")
                            Spacer()
                            Text("\(model.binCount)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            // Room so the last row can scroll above the floating button.
            .contentMargins(.bottom, 76, for: .scrollContent)
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

/// Floating "New Project" pill at the bottom of the projects list.
struct NewProjectButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New Project", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 20)
                .frame(minHeight: 48)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Creates an empty project without recording")
    }
}

/// Centered pop-up bubble for naming a new project, styled like an iOS
/// alert. The field starts with the default name fully selected, so typing
/// replaces it and Create keeps it. Calls back with nil on Cancel.
struct NewProjectBubble: View {
    let defaultName: String
    let onFinish: (String?) -> Void
    @State private var name: String

    init(defaultName: String, onFinish: @escaping (String?) -> Void) {
        self.defaultName = defaultName
        self.onFinish = onFinish
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onFinish(nil) }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("New Project")
                        .font(.headline)
                    SelectAllTextField(text: $name, placeholder: defaultName) {
                        onFinish(name.isEmpty ? defaultName : name)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .tertiarySystemFill)))
                }
                .padding(16)

                Divider()
                HStack(spacing: 0) {
                    Button("Cancel") { onFinish(nil) }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    Divider().frame(height: 44)
                    Button("Create") { onFinish(name.isEmpty ? defaultName : name) }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }
}

/// UITextField that takes focus and selects all its text when shown.
struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.text = text
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.autocapitalizationType = .words
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        DispatchQueue.main.async {
            field.becomeFirstResponder()
            field.selectAll(nil)
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        init(_ parent: SelectAllTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
