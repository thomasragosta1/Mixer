import SwiftUI
import UIKit
import FourTrackCore

/// One open project. Record mode shows four stacked lanes with a shared
/// playhead; Mix mode flips the same screen into four channel strips.
struct ProjectView: View {
    @State private var model: ProjectViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingExport = false
    @State private var showingSettings = false
    @State private var renamingProject = false
    @State private var draftName = ""
    @State private var scrubStart: Double?
    private let onDelete: (Project) -> Void
    private let startRecordingOnAppear: Bool

    init(project: Project, store: ProjectStore, startRecording: Bool = false, onDelete: @escaping (Project) -> Void) {
        // Autoclosure init: the model (and its audio engine) is built once per screen.
        _model = State(wrappedValue: ProjectViewModel(project: project, store: store))
        self.onDelete = onDelete
        startRecordingOnAppear = startRecording
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.mixMode {
                MixView(model: model)
            } else {
                lanes
            }
            if let offer = model.cleanupOffer {
                CleanupBanner(trackName: model.project.tracks[offer].name) {
                    model.acceptCleanupOffer()
                } onDismiss: {
                    model.cleanupOffer = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            TransportView(model: model)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.default, value: model.cleanupOffer)
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showingExport) {
            ExportSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSettings, onDismiss: { model.developerModeChanged() }) {
            SettingsView(model: model, settings: model.settings)
        }
        .alert("Rename Project", isPresented: $renamingProject) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.renameProject(to: draftName) }
        }
        .alert("Microphone Access Is Off", isPresented: $model.showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Four-Track needs the microphone to record. You can turn it on in Settings.")
        }
        .alert("Tip: Use Wired Headphones for Overdubs", isPresented: $model.showBluetoothTip) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bluetooth adds a large, variable delay, so new parts may not line up with what you hear. Wired headphones or the speaker keep layers tight.")
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            model.activate()
            if startRecordingOnAppear && !model.hasAnyAudio && !model.isRecording {
                Task { await model.startRecording() }
            }
        }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.enteredBackground() }
        }
    }

    // MARK: Lanes

    /// Lanes as separate cards in a List: press and hold a card to drag it
    /// up or down (not while recording). Drag sideways on a waveform to scrub.
    private var lanes: some View {
        List {
            ForEach(model.visibleLanes, id: \.self) { i in
                TrackRowView(model: model, index: i, onScrub: scrubGesture)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                model.moveLanes(fromOffsets: source, toOffset: destination)
            }
            .moveDisabled(model.isRecording || model.isSaving)

            if model.visibleTrackCount < Project.trackCount {
                AddTrackButton(nextNumber: model.visibleTrackCount + 1) { model.addTrack() }
                    .disabled(model.isRecording || model.isSaving)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.visibleLanes)
    }

    /// Drag a waveform sideways to scrub, like Voice Memos.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard !model.isRecording, abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
                if scrubStart == nil {
                    scrubStart = model.playhead
                    model.beginScrub()
                }
                let seconds = (scrubStart ?? 0) - Double(g.translation.width / WaveformView.defaultPointsPerSecond)
                model.scrub(to: seconds)
            }
            .onEnded { _ in
                if scrubStart != nil {
                    scrubStart = nil
                    model.endScrub()
                }
            }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Button {
                draftName = model.project.name
                renamingProject = true
            } label: {
                Text(model.project.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .accessibilityHint("Renames the project")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.mixMode.toggle()
            } label: {
                Image(systemName: "slider.vertical.3")
                    .symbolVariant(model.mixMode ? .fill : .none)
                    .foregroundStyle(model.mixMode ? Color.accentColor : Color.primary)
            }
            .accessibilityLabel(model.mixMode ? "Show tracks" : "Show mixer")

            Button {
                showingExport = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(!model.hasAnyAudio || model.isRecording)
            .accessibilityLabel("Export")

            Menu {
                Button {
                    draftName = model.project.name
                    renamingProject = true
                } label: {
                    Label("Rename Project", systemImage: "pencil")
                }
                let i = model.armedTrack
                if !model.project.tracks[i].isEmpty {
                    Button {
                        model.update(track: i) { if $0.cleanup == 0 { $0.cleanup = 0.6 } }
                        model.runCleanup(i)
                    } label: {
                        Label("Clean Up \(model.project.tracks[i].name)", systemImage: "wand.and.stars")
                    }
                    .disabled(model.cleanupProgress[i] != nil || model.project.tracks[i].cleanedFileName != nil)
                }
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                Divider()
                Button(role: .destructive) {
                    // Goes to Recently Deleted; permanent deletion only happens there.
                    let project = model.project
                    model.close()
                    dismiss()
                    onDelete(project)
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(model.isRecording)
            .accessibilityLabel("More")
        }
    }
}

/// The "+" under the last lane that reveals the next track.
struct AddTrackButton: View {
    let nextNumber: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Add Track \(nextNumber)")
    }
}

/// Non-blocking offer after a speaker-route take: "Clean up this take?"
struct CleanupBanner: View {
    let trackName: String
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Clean up this take?")
                    .font(.subheadline.weight(.semibold))
                Text("Reduces noise and backing-track bleed on \(trackName).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Clean Up", action: onAccept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

/// UIActivityViewController for exported files.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
