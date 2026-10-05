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
                RecordButton(isRecording: false) { newProject(record: true) }
                    .padding(.vertical, 14)
                    .accessibilityLabel("New recording")
                    .accessibilityHint("Creates a project and starts recording on Track 1")
            }
            .background(Color(uiColor: .systemBackground))
            // The keyboard slides over the list and buttons instead of pushing them up.
            // The naming bubble (an overlay) still sits above the keyboard.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .navigationTitle("All Projects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                    Button {
                        path.append(.bin)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Recently Deleted")
                    .accessibilityValue(model.binCount == 0 ? "Empty" : "\(model.binCount) projects")
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
                    NewProjectBubble(defaultName: model.nextDefaultName) { name, mode in
                        withAnimation(.easeOut(duration: 0.15)) { namingNewProject = false }
                        guard let name, let project = model.createProject(named: name, mode: mode) else { return }
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
        if model.projects.isEmpty {
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
                        .listRowInsets(EdgeInsets(top: 9, leading: 20, bottom: 9, trailing: 20))
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(.project(project.id, record: false)) }
                        .onLongPressGesture {
                            Haptics.hold()
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.headline)
                    .lineLimit(1)
                if project.mode == .simple {
                    Text("Simple")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(Self.dateLabel(project.createdAt))
                Spacer()
                Text(TimeFormat.duration(project.durationSeconds))
                    .monospacedDigit()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    /// Voice Memos style: a time for today, "Yesterday", then the date.
    static func dateLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Floating "New Project" pill at the bottom of the projects list.
struct NewProjectButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("New Project", systemImage: "plus")
                .font(.headline)
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
        }
        .prominentGlassButton()
        .controlSize(.large)
        .accessibilityHint("Creates an empty project without recording")
    }
}

/// Centered pop-up bubble for naming a new project, styled like an iOS
/// alert. The field starts with the default name fully selected, so typing
/// replaces it and Create keeps it. Calls back with nil on Cancel.
struct NewProjectBubble: View {
    let defaultName: String
    /// Name (nil = cancelled) and the project's mode.
    let onFinish: (String?, ProjectMode) -> Void
    @State private var name: String
    @State private var mode: ProjectMode = .full

    init(defaultName: String, onFinish: @escaping (String?, ProjectMode) -> Void) {
        self.defaultName = defaultName
        self.onFinish = onFinish
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onFinish(nil, mode) }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Text("New Project")
                        .font(.headline)
                    SelectAllTextField(text: $name, placeholder: defaultName) {
                        onFinish(name.isEmpty ? defaultName : name, mode)
                    }
                    .frame(height: 36)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    Picker("Mode", selection: $mode) {
                        Text("Full").tag(ProjectMode.full)
                        Text("Simple").tag(ProjectMode.simple)
                    }
                    .pickerStyle(.segmented)
                    Text(mode == .full ? "Everything: drums, mixer, metronome, quantize." : "Just audio tracks, volume and Clean Up. Switch any time from ⋯.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    Button { onFinish(nil, mode) } label: {
                        Text("Cancel").frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .glassButton()
                    Button { onFinish(name.isEmpty ? defaultName : name, mode) } label: {
                        Text("Create").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .prominentGlassButton()
                }
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 300)
            .glassPanel(cornerRadius: 32)
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
