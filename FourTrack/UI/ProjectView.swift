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
    /// Where the held card is, per frame. Kept out of `laneDrag` so following
    /// the finger only redraws that one card, not the whole screen.
    @State private var laneMotion = LaneMotion()
    /// Wider than tall (landscape, or an unfolded inner display): the
    /// transport sits beside the tracks instead of under them.
    @State private var isWide = false
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

    /// For the in-app tests: a screen around an existing model.
    init(model: ProjectViewModel, onDelete: @escaping (Project) -> Void = { _ in }) {
        _model = State(wrappedValue: model)
        self.onDelete = onDelete
        startRecordingOnAppear = false
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
            } else if model.showsDrumPads {
                // Drum layout: slim lanes, big pads, one-row transport.
                DrumStudioView(model: model) { pendingTrackDelete = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isWide {
                HStack(alignment: .top, spacing: 0) {
                    lanes
                        .zIndex(laneDrag != nil ? 1 : 0)
                    ScrollView {
                        if model.isDrumArmed { PadsPullTab(model: model) }
                        transport
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 360)
                }
                .transition(.opacity)
            } else {
                lanes
                    .zIndex(laneDrag != nil ? 1 : 0)
                    .transition(.opacity)
            }
            if !model.mixMode && !model.showsDrumPads && !isWide {
                if model.isDrumArmed { PadsPullTab(model: model) }
                transport
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.width > $0.size.height * 1.1 }) { isWide = $0 }
        // Track cards, strips and pads have fixed sizes; past XXXL their text
        // would clip. Buttons there offer the Large Content Viewer instead,
        // and sheets and lists opened from here scale fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) {
            if laneDrag != nil {
                TrackBinDropZone(isTargeted: laneDrag?.overBin == true)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { laneMotion.binFrame = $0 }
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: laneDrag != nil)
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
            Text("Simple mode only has audio tracks. Press and hold each drum track and drag it to the bin, then switch to Simple mode.")
        }
        .sheet(isPresented: $showingTrackBin) {
            TrackBinView(model: model)
                .presentationDetents([.medium, .large])
        }
        .animation(PadsDrawer.animation, value: model.showsDrumPads)
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
        .onDisappear {
            model.close()
            Hints.shared.screenDisappeared()
        }
        .hintBubble([.dragTrackToBin, .padSound, .metronomeHolds])
        .onChange(of: wantedHint, initial: true) { _, hint in
            if let hint { Hints.shared.request(hint) } else { Hints.shared.cancelPending() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.enteredBackground() }
        }
    }

    /// The press-and-hold tip worth showing for what's on screen now.
    private var wantedHint: HoldHint? {
        guard !model.isRecording, !model.isSaving, !model.mixMode, laneDrag == nil else { return nil }
        let hints = Hints.shared
        guard hints.current == nil else { return nil }
        var candidates: [HoldHint] = []
        if model.showsDrumPads { candidates.append(.padSound) }
        if !model.isSimple && model.project.metronome.enabled { candidates.append(.metronomeHolds) }
        if !model.showsDrumPads && model.hasAnyAudio { candidates.append(.dragTrackToBin) }
        return candidates.first { !hints.hasSeen($0) }
    }

    private var transport: some View {
        TransportView(model: model)
            .padding(.vertical, 4)
            .glassPanel()
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
    }

    // MARK: Lanes

    /// A lane being dragged after a press and hold. Only changes when the
    /// drag starts, crosses into another slot, or reaches the bin.
    struct LaneDrag: Equatable {
        let index: Int
        let startPosition: Int
        var target: Int
        var overBin = false
    }

    private static let laneSpacing: CGFloat = 12
    private var laneStep: CGFloat { TrackRowView<DragGesture>.cardHeight(simple: model.isSimple) + Self.laneSpacing }

    /// Lanes as separate cards. Press and hold a card (briefly), then drag it
    /// up or down to reorder, or onto the bin that rises at the bottom to
    /// delete it (not while recording). Drag sideways on a waveform to scrub.
    private var lanes: some View {
        let order = model.visibleLanes
        return ScrollView {
            VStack(spacing: Self.laneSpacing) {
                ForEach(Array(order.enumerated()), id: \.element) { position, i in
                    let dragging = laneDrag?.index == i
                    let overBin = dragging && laneDrag?.overBin == true
                    TrackRowView(model: model, index: i, onScrub: scrubGesture)
                        // Only the card lifts: shadow and scale follow its rounded shape.
                        .compositingGroup()
                        .shadow(color: .black.opacity(dragging ? 0.22 : 0), radius: dragging ? 18 : 0, y: dragging ? 10 : 0)
                        .scaleEffect(dragging ? (overBin ? 0.55 : 1.04) : 1, anchor: .center)
                        .opacity(overBin ? 0.7 : 1)
                        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: dragging)
                        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: overBin)
                        // The other cards glide out of the held card's way.
                        .offset(y: laneOffset(position: position, index: i))
                        .animation(.spring(response: 0.26, dampingFraction: 0.85), value: laneOffset(position: position, index: i))
                        // The held card follows the finger 1:1.
                        .modifier(FollowsFinger(motion: laneMotion, index: i))
                        .zIndex(dragging || laneMotion.index == i ? 1 : 0)
                        .simultaneousGesture(laneGesture(index: i, position: position, count: order.count))
                        .accessibilityAction(named: "Delete track") { pendingTrackDelete = i }
                        .accessibilityAction(named: "Move up") {
                            guard position > 0, !model.isRecording else { return }
                            model.moveLanes(fromOffsets: IndexSet(integer: position), toOffset: position - 1)
                        }
                        .accessibilityAction(named: "Move down") {
                            guard position < order.count - 1, !model.isRecording else { return }
                            model.moveLanes(fromOffsets: IndexSet(integer: position), toOffset: position + 2)
                        }
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
        .modifier(WaveformPinch(model: model))
        // Let the held card travel past the list (down to the bin) without being clipped.
        .scrollClipDisabled(laneDrag != nil)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.visibleLanes)
    }

    /// Cards between the held card's old and new slot shift by one slot.
    private func laneOffset(position: Int, index: Int) -> CGFloat {
        guard let d = laneDrag, d.index != index, !d.overBin else { return 0 }
        if position > d.startPosition && position <= d.target { return -laneStep }
        if position < d.startPosition && position >= d.target { return laneStep }
        return 0
    }

    private func laneGesture(index: Int, position: Int, count: Int) -> some Gesture {
        // A short hold (0.2 s) picks the card up; it then tracks the finger
        // from the very first movement.
        LongPressGesture(minimumDuration: 0.2, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard !model.isRecording, !model.isSaving, scrubStart == nil else { return }
                guard case .second(true, let drag) = value else { return }
                if laneDrag == nil {
                    laneMotion.index = index
                    laneMotion.y = 0
                    laneDrag = LaneDrag(index: index, startPosition: position, target: position)
                    Hints.shared.dismiss(.dragTrackToBin)
                    Haptics.lift.impactOccurred()
                    Haptics.slot.prepare()
                    Haptics.delete.prepare()
                }
                guard let drag, var d = laneDrag else { return }
                laneMotion.y = drag.translation.height
                // Rare changes only: a new slot, or reaching the bin.
                let over = laneMotion.binFrame.insetBy(dx: -30, dy: -30).contains(drag.location)
                let moved = Int((drag.translation.height / laneStep).rounded())
                let target = min(max(position + moved, 0), count - 1)
                if over != d.overBin {
                    d.overBin = over
                    (over ? Haptics.delete : Haptics.lift).impactOccurred()
                }
                if target != d.target && !over {
                    d.target = target
                    Haptics.slot.selectionChanged()
                }
                if d != laneDrag { laneDrag = d }
            }
            .onEnded { _ in
                guard let d = laneDrag else { return }
                if d.overBin {
                    pendingTrackDelete = d.index
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        laneDrag = nil
                        laneMotion.y = 0
                    } completion: {
                        laneMotion.index = nil
                    }
                    return
                }
                // Drop: reorder with no animation, keeping the card exactly under
                // the finger, then let it settle into its slot with one spring.
                let residual = laneMotion.y - CGFloat(d.target - d.startPosition) * laneStep
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    if d.target != d.startPosition {
                        model.moveLanes(fromOffsets: IndexSet(integer: d.startPosition), toOffset: d.target > d.startPosition ? d.target + 1 : d.target)
                    }
                    laneDrag = nil
                    laneMotion.y = residual
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    laneMotion.y = 0
                } completion: {
                    laneMotion.index = nil
                }
            }
    }

    /// Drag a waveform sideways to scrub, like Voice Memos.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard !model.isRecording, !model.isZooming, laneDrag == nil, abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
                if scrubStart == nil {
                    scrubStart = model.playhead
                    model.beginScrub()
                }
                let seconds = (scrubStart ?? 0) - Double(g.translation.width / (WaveformView.defaultPointsPerSecond * model.effectiveZoom))
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

/// Above the transport while a drum track's pads are put away: just the
/// grabber. Swipe up on it (or tap it) to bring the pads back. It never moves
/// with the finger.
struct PadsPullTab: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        GrabberBar()
            .frame(minHeight: 30)
            .onTapGesture { show() }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { g in
                        if g.translation.height < -16 || g.predictedEndTranslation.height < -60 { show() }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Show drum pads")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { show() }
    }

    private func show() {
        guard model.drumPadsHidden else { return }
        Haptics.slot.selectionChanged()
        withAnimation(PadsDrawer.animation) { model.drumPadsHidden = false }
    }
}

/// The held card's position, updated every frame of a drag. Observed only
/// by `FollowsFinger`, so moving it redraws just that card.
@Observable
final class LaneMotion {
    var index: Int?
    var y: CGFloat = 0
    @ObservationIgnored var binFrame: CGRect = .zero
}

/// Offsets the held card by the finger's movement.
struct FollowsFinger: ViewModifier {
    let motion: LaneMotion
    let index: Int

    func body(content: Content) -> some View {
        content.offset(y: motion.index == index ? motion.y : 0)
    }
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
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isTargeted)
        .accessibilityHidden(true)
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

/// Full mode: pinch the tracks to zoom the waveforms in and out. Snaps to the
/// standard scale with a tick on the way through.
struct WaveformPinch: ViewModifier {
    let model: ProjectViewModel
    @State private var startZoom: Double?

    func body(content: Content) -> some View {
        if model.isSimple {
            content
        } else {
            content
                .simultaneousGesture(
                    MagnifyGesture(minimumScaleDelta: 0.02)
                        .onChanged { value in
                            guard !model.isRecording else { return }
                            if startZoom == nil {
                                startZoom = model.waveformZoom
                                model.isZooming = true
                            }
                            let range = ProjectViewModel.zoomRange
                            let raw = min(max((startZoom ?? 1) * value.magnification, range.lowerBound), range.upperBound)
                            // A small detent at the standard scale.
                            let z = abs(raw - 1) < 0.07 ? 1 : raw
                            let before = model.waveformZoom
                            if (z == 1) != (before == 1) || ((z == range.lowerBound || z == range.upperBound) && z != before) {
                                Haptics.slot.selectionChanged()
                            }
                            if z != before { model.waveformZoom = z }
                        }
                        .onEnded { _ in
                            startZoom = nil
                            model.isZooming = false
                        }
                )
                .accessibilityZoomAction { action in
                    model.stepZoom(in: action.direction == .zoomIn)
                }
        }
    }
}
