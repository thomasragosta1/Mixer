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
    @State private var pendingTrackDelete: Int?
    @State private var showingTrackBin = false
    @State private var confirmingSimpleMode = false
    @State private var showingDrumsBlockSimple = false
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
            if !model.mixMode && !model.isDrumArmed {
                TransportView(model: model)
                    .padding(.vertical, 4)
                    .glassPanel()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            Text("Simple mode hides the mixer's tone and effects, mute and solo, and the metronome, so those are reset to their defaults. Volume and Clean Up stay. You can undo this.")
        }
        .alert("Delete Drum Tracks First", isPresented: $showingDrumsBlockSimple) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Simple mode only has audio tracks. Swipe left from the right edge of each drum track to delete it, then switch to Simple mode.")
        }
        .sheet(isPresented: $showingTrackBin) {
            TrackBinView(model: model)
                .presentationDetents([.medium, .large])
        }
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
    private var laneStep: CGFloat { TrackRowView<DragGesture>.cardHeight(simple: model.isSimple) + Self.laneSpacing }

    /// Lanes as separate cards. Press and hold a card, then drag it up or down
    /// to reorder; swipe in from a card's right edge to delete it (not while
    /// recording). Drag sideways on a waveform to scrub.
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
                        .scaleEffect(dragging ? 1.04 : 1, anchor: .center)
                        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: dragging)
                        // Swipe in from the card's right edge to delete it.
                        .modifier(EdgeSwipeToDelete(
                            enabled: !model.isRecording && !model.isSaving && laneDrag == nil,
                            onTap: { model.arm(i) },
                            onDelete: { pendingTrackDelete = i }
                        ))
                        // The held card tracks the finger 1:1 with no animation lag;
                        // the others glide out of its way.
                        .offset(y: laneOffset(position: position, index: i, count: order.count))
                        .animation(dragging ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: laneOffset(position: position, index: i, count: order.count))
                        .zIndex(dragging ? 1 : 0)
                        .simultaneousGesture(laneGesture(index: i, position: position, count: order.count))
                        .accessibilityAction(named: "Delete track") { pendingTrackDelete = i }
                }

                if model.visibleTrackCount < Project.trackCount {
                    AddTrackButton(nextNumber: model.visibleTrackCount + 1, audioOnly: model.isSimple) { kind in model.addTrack(kind: kind) }
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
                if targetPosition(count: count) != before { Haptics.slot.selectionChanged() }
            }
            .onEnded { _ in
                guard let d = laneDrag else { return }
                let target = targetPosition(count: count)
                if target != d.startPosition {
                    model.moveLanes(fromOffsets: IndexSet(integer: d.startPosition), toOffset: target > d.startPosition ? target + 1 : target)
                }
                // Drop: the card settles into its new slot with one spring.
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    laneDrag = nil
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
                let before = model.playhead
                model.scrub(to: seconds)
                Haptics.scrubTick(from: before, to: model.playhead, grid: model.beatGrid, end: model.duration)
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
                if model.project.tracks[i].isEmpty && !model.isSimple {
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
                        } else if model.simpleModeBlockedByDrums {
                            showingDrumsBlockSimple = true
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
    static let delete = UIImpactFeedbackGenerator(style: .heavy)
    static let slot = UISelectionFeedbackGenerator()

    /// The little buzz for every press-and-hold in the app.
    static func hold() { lift.impactOccurred() }

    /// While scrubbing: a tick on every bar line when the metronome's grid is
    /// showing, and at the start and end of the song, so you can feel your place.
    static func scrubTick(from old: Double, to new: Double, grid: BeatGrid?, end: Double) {
        guard old != new else { return }
        let hitEdge = (new <= 0 && old > 0) || (new >= end && old < end)
        var crossedBar = false
        if let grid {
            let n = Double(max(1, grid.beatsPerBar))
            crossedBar = (grid.beat(at: old) / n).rounded(.down) != (grid.beat(at: new) / n).rounded(.down)
        }
        if hitEdge || crossedBar { slot.selectionChanged() }
    }
}

/// iOS-style swipe to delete, started on the card's right edge: the card
/// follows the finger left, uncovering a red trash; let go past the threshold
/// (or flick) and `onDelete` runs (it asks "are you sure"), and the card
/// springs back. Starting anywhere else on the card leaves scrubbing and the
/// other gestures alone.
struct EdgeSwipeToDelete: ViewModifier {
    var enabled = true
    var cornerRadius: CGFloat = Theme.cardRadius
    /// How wide the grab strip on the right edge is.
    var edgeWidth: CGFloat = 30
    /// Taps on the strip still do what a tap on the card does.
    var onTap: (() -> Void)? = nil
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 1
    @State private var pastThreshold = false

    private var threshold: CGFloat { min(width * 0.4, 160) }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .overlay(alignment: .trailing) {
                if enabled {
                    AxisPan(
                        axis: .horizontal,
                        onChanged: changed,
                        onEnded: ended,
                        onDoubleTap: nil,
                        onTap: onTap
                    )
                    .frame(width: edgeWidth)
                    .offset(x: offset)
                }
            }
            .background(alignment: .trailing) {
                // Only visible while the card is pulled aside.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.red)
                    .overlay(alignment: .trailing) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .scaleEffect(pastThreshold ? 1.25 : 1)
                            .frame(width: max(0, -offset))
                            .opacity(min(1, Double(-offset / 40)))
                    }
                    .frame(width: max(0, -offset + cornerRadius))
                    .opacity(offset < 0 ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = max(1, $0) }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pastThreshold)
    }

    private func changed(_ travel: CGFloat) {
        // Leftwards only; resist past most of the width.
        let raw = min(0, travel)
        let limit = width * 0.85
        offset = raw > -limit ? raw : -limit - (-raw - limit) * 0.2
        let past = -offset >= threshold
        if past != pastThreshold {
            pastThreshold = past
            (past ? Haptics.delete : Haptics.lift).impactOccurred()
        }
    }

    private func ended() {
        let delete = pastThreshold
        pastThreshold = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { offset = 0 }
        if delete { onDelete() }
    }
}

/// The "+" under the last lane. Tapping it asks for the kind of track.
struct AddTrackButton: View {
    let nextNumber: Int
    var height: CGFloat = 52
    /// Simple projects: tapping adds an audio track straight away.
    var audioOnly = false
    let action: (TrackKind) -> Void

    init(nextNumber: Int, height: CGFloat = 52, audioOnly: Bool = false, action: @escaping (TrackKind) -> Void) {
        self.nextNumber = nextNumber
        self.height = height
        self.audioOnly = audioOnly
        self.action = action
    }

    var body: some View {
        if audioOnly {
            Button { action(.audio) } label: { plus }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Add Track \(nextNumber)")
        } else {
            menu
        }
    }

    private var plus: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(Rectangle())
    }

    private var menu: some View {
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
            plus
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel("Add Track \(nextNumber)")
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
