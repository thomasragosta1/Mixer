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
    @State private var laneDrag: LaneDrag?
    @State private var overBin = false
    @State private var binFrame: CGRect = .zero
    @State private var pendingTrackDelete: Int?
    @State private var showingTrackBin = false
    @State private var confirmingSimpleMode = false
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
            // Simple projects have no mixer: just recording.
            if !model.isSimple {
                Picker("Mode", selection: $model.mixMode) {
                    Text("Record").tag(false)
                    Text("Mixing").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .disabled(model.isRecording || model.isSaving)
            }

            if model.mixMode && !model.isSimple {
                MixView(model: model)
            } else if model.isDrumArmed {
                // Drum layout: slim lanes, big pads, one-row transport.
                DrumStudioView(model: model) { pendingTrackDelete = $0 }
                    .transition(.opacity)
            } else {
                lanes
                    .zIndex(laneDrag != nil ? 1 : 0)
                    .transition(.opacity)
            }
            if !model.mixMode, let offer = model.cleanupOffer {
                CleanupBanner(trackName: model.project.tracks[offer].name) {
                    model.acceptCleanupOffer()
                } onDismiss: {
                    model.cleanupOffer = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if !model.mixMode && !model.isDrumArmed {
                TransportView(model: model)
                    .padding(.vertical, 4)
                    .glassPanel()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) {
            if laneDrag != nil {
                TrackBinDropZone(isTargeted: overBin)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { binFrame = $0 }
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: laneDrag != nil)
        .alert(
            "Are you sure you want to delete this track?",
            isPresented: Binding(get: { pendingTrackDelete != nil }, set: { if !$0 { pendingTrackDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let i = pendingTrackDelete { model.deleteTrack(i) }
                pendingTrackDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingTrackDelete = nil }
        } message: {
            if let i = pendingTrackDelete {
                Text("\u{201C}\(model.project.tracks[i].name)\u{201D} will move to Recently Deleted in this project.")
            }
        }
        .alert("Switch to Simple Mode?", isPresented: $confirmingSimpleMode) {
            Button("Switch") { model.switchToSimpleMode() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Simple mode hides the mixer, mute and solo, the metronome, quantize and the extra drum kits and pad settings, so those are reset to their defaults. Clean Up, pad volume and tone stay. You can undo this.")
        }
        .sheet(isPresented: $showingTrackBin) {
            TrackBinView(model: model)
                .presentationDetents([.medium, .large])
        }
        .animation(.default, value: model.cleanupOffer)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.isDrumArmed)
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
        .alert("Headphones Suggested", isPresented: $model.showMetronomeHeadphoneTip) {
            Button("Record Anyway") { Task { await model.startRecording(skipHeadphoneTip: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The metronome is playing through the speaker, so the microphone will pick it up and it will be on your track. Plug in headphones to keep the click off the recording, or set the metronome to Silent to just see the beat.")
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

    /// A lane being dragged after a press and hold.
    struct LaneDrag: Equatable {
        let index: Int
        let startPosition: Int
        var translation: CGFloat = 0
    }

    private static let laneSpacing: CGFloat = 12
    private var laneStep: CGFloat { TrackRowView<DragGesture>.cardHeight + Self.laneSpacing }

    /// Lanes as separate cards. Press and hold a card, then drag it up or down
    /// to reorder, or onto the bin that appears at the bottom to delete it
    /// (not while recording). Drag sideways on a waveform to scrub.
    private var lanes: some View {
        let order = model.visibleLanes
        return ScrollView {
            VStack(spacing: Self.laneSpacing) {
                ForEach(Array(order.enumerated()), id: \.element) { position, i in
                    let dragging = laneDrag?.index == i
                    TrackRowView(model: model, index: i, onScrub: scrubGesture)
                        // Only the card lifts: shadow and scale follow its rounded shape.
                        .compositingGroup()
                        .shadow(color: .black.opacity(dragging ? 0.22 : 0), radius: dragging ? 18 : 0, y: dragging ? 10 : 0)
                        .scaleEffect(dragging ? (overBin ? 0.55 : 1.04) : 1, anchor: .center)
                        .opacity(dragging && overBin ? 0.7 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: dragging)
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: overBin)
                        // The held card tracks the finger 1:1 with no animation lag;
                        // the others glide out of its way.
                        .offset(y: laneOffset(position: position, index: i, count: order.count))
                        .animation(dragging ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: laneOffset(position: position, index: i, count: order.count))
                        .zIndex(dragging ? 1 : 0)
                        .simultaneousGesture(laneGesture(index: i, position: position, count: order.count))
                        .accessibilityAction(named: "Delete track") { pendingTrackDelete = i }
                }

                if model.visibleTrackCount < Project.trackCount {
                    AddTrackButton(nextNumber: model.visibleTrackCount + 1) { kind in model.addTrack(kind: kind) }
                        .disabled(model.isRecording || model.isSaving)
                        .opacity(laneDrag == nil ? 1 : 0.3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollDisabled(laneDrag != nil)
        // Let the held card travel past the list (down to the bin) without being clipped.
        .scrollClipDisabled(laneDrag != nil)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.visibleLanes)
    }

    private func targetPosition(count: Int) -> Int {
        guard let d = laneDrag else { return -1 }
        let moved = Int((d.translation / laneStep).rounded())
        return min(max(d.startPosition + moved, 0), count - 1)
    }

    /// The dragged card follows the finger; the others slide out of its way.
    private func laneOffset(position: Int, index: Int, count: Int) -> CGFloat {
        guard let d = laneDrag else { return 0 }
        if d.index == index { return d.translation }
        if overBin { return 0 }
        let target = targetPosition(count: count)
        if position > d.startPosition && position <= target { return -laneStep }
        if position < d.startPosition && position >= target { return laneStep }
        return 0
    }

    private func laneGesture(index: Int, position: Int, count: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard !model.isRecording, !model.isSaving, scrubStart == nil else { return }
                guard case .second(true, let drag) = value else { return }
                if laneDrag == nil {
                    laneDrag = LaneDrag(index: index, startPosition: position)
                    Haptics.lift.impactOccurred()
                    Haptics.slot.prepare()
                }
                guard let drag else { return }
                let before = targetPosition(count: count)
                laneDrag?.translation = drag.translation.height
                if targetPosition(count: count) != before && !overBin { Haptics.slot.selectionChanged() }
                let over = binFrame.insetBy(dx: -24, dy: -24).contains(drag.location)
                if over != overBin {
                    overBin = over
                    (over ? Haptics.bin : Haptics.lift).impactOccurred()
                }
            }
            .onEnded { _ in
                guard let d = laneDrag else { return }
                if overBin {
                    pendingTrackDelete = d.index
                } else {
                    let target = targetPosition(count: count)
                    if target != d.startPosition {
                        model.moveLanes(fromOffsets: IndexSet(integer: d.startPosition), toOffset: target > d.startPosition ? target + 1 : target)
                    }
                }
                // Drop: the card settles into its new slot with one spring.
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    laneDrag = nil
                    overBin = false
                }
            }
    }

    /// Drag a waveform sideways to scrub, like Voice Memos.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard !model.isRecording, laneDrag == nil, abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
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
        ToolbarItemGroup(placement: .topBarLeading) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo || model.isUndoBlocked)
            .accessibilityLabel(model.undoLabel.map { "Undo \($0)" } ?? "Undo")
            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo || model.isUndoBlocked)
            .accessibilityLabel(model.redoLabel.map { "Redo \($0)" } ?? "Redo")
        }
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
            Menu {
                // Share lives in the menu so the top bar stays uncluttered.
                Button {
                    showingExport = true
                } label: {
                    Label("Share / Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.hasAnyAudio || model.isRecording)
                Divider()
                Button {
                    draftName = model.project.name
                    renamingProject = true
                } label: {
                    Label("Rename Project", systemImage: "pencil")
                }
                let i = model.armedTrack
                if model.project.tracks[i].isEmpty {
                    let drums = model.project.tracks[i].isDrums
                    Button {
                        model.setKind(i, drums ? .audio : .drums)
                    } label: {
                        Label(drums ? "Make \(model.project.tracks[i].name) an Audio Track" : "Make \(model.project.tracks[i].name) a Drum Track",
                              systemImage: drums ? "mic" : "square.grid.3x2")
                    }
                }
                if !model.project.tracks[i].isEmpty && !model.project.tracks[i].isDrums {
                    Button {
                        model.update(track: i) { if $0.cleanup == 0 { $0.cleanup = 0.6 } }
                        model.runCleanup(i)
                    } label: {
                        Label("Clean Up \(model.project.tracks[i].name)", systemImage: "wand.and.stars")
                    }
                    .disabled(model.cleanupProgress[i] != nil || model.project.tracks[i].cleanedFileName != nil)
                }
                Button {
                    showingTrackBin = true
                } label: {
                    Label("Recently Deleted", systemImage: "trash")
                }
                Toggle(isOn: Binding(
                    get: { model.isSimple },
                    set: { simple in
                        if !simple {
                            model.switchToFullMode()
                        } else if model.simpleModeResetsSettings {
                            confirmingSimpleMode = true
                        } else {
                            model.switchToSimpleMode()
                        }
                    }
                )) {
                    Label("Simple Mode", systemImage: "circle.grid.2x1")
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

enum Haptics {
    static let lift = UIImpactFeedbackGenerator(style: .medium)
    static let bin = UIImpactFeedbackGenerator(style: .heavy)
    static let slot = UISelectionFeedbackGenerator()

    /// The little buzz for every press-and-hold in the app.
    static func hold() { lift.impactOccurred() }
}

/// Bin that rises from the bottom while a lane is held; drop a lane on it to delete.
struct TrackBinDropZone: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: isTargeted ? "trash.fill" : "trash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isTargeted ? .white : .red)
                .frame(width: 72, height: 72)
                .background(Circle().fill(isTargeted ? Color.red : Color.red.opacity(0.12)))
                .scaleEffect(isTargeted ? 1.15 : 1)
            Text(isTargeted ? "Release to Delete" : "Drag Here to Delete")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isTargeted ? .red : .secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .glassPanel(cornerRadius: 28)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isTargeted)
        .accessibilityHidden(true)
    }
}

/// The "+" under the last lane. Tapping it asks for the kind of track.
struct AddTrackButton: View {
    let nextNumber: Int
    var height: CGFloat = 52
    let action: (TrackKind) -> Void

    init(nextNumber: Int, height: CGFloat = 52, action: @escaping (TrackKind) -> Void) {
        self.nextNumber = nextNumber
        self.height = height
        self.action = action
    }

    var body: some View {
        Menu {
            Button {
                action(.audio)
            } label: {
                Label("Audio Track", systemImage: "mic")
            }
            Button {
                action(.drums)
            } label: {
                Label("Drum Track", systemImage: "square.grid.3x2")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
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
                .prominentGlassButton()
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
        .glassPanel(cornerRadius: 24)
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
