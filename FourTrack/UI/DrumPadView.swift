import SwiftUI
import UIKit
import FourTrackCore

/// Record mode while a drum track is armed. The screen is rebuilt around
/// playing: the lanes shrink to slim rows (still tappable to switch tracks),
/// the pads take most of the screen, and the transport becomes a compact
/// panel with the metronome on top. Press and hold a pad to adjust its sound.
struct DrumStudioView: View {
    @Bindable var model: ProjectViewModel
    let onDeleteTrack: (Int) -> Void
    @State private var editingPad: PadID?

    struct PadID: Identifiable { let id: Int }

    private var index: Int { model.armedTrack }
    private var track: Track { model.project.tracks[index] }

    /// Wider than tall (landscape, or an unfolded inner display): controls in
    /// a column on the left, the pads filling the right.
    @State private var isWide = false

    var body: some View {
        Group {
            if isWide {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        VStack(spacing: 10) {
                            CompactLaneList(model: model, onDeleteTrack: onDeleteTrack)
                            trackControls
                            transportPanel
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 380)
                    pads
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 10) {
                    CompactLaneList(model: model, onDeleteTrack: onDeleteTrack)
                    trackControls
                    pads
                    transportPanel
                }
            }
        }
        .onGeometryChange(for: Bool.self, of: { $0.size.width > $0.size.height * 1.1 }) { isWide = $0 }
        .padding(.top, 2)
        .sheet(item: $editingPad) { item in
            PadSettingsSheet(model: model, trackIndex: index, pad: item.id)
        }
    }

    @ViewBuilder private var trackControls: some View {
        if model.isSimple {
            Text(track.name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
        } else {
            DrumTrackControls(model: model, index: index)
                .padding(.horizontal, 16)

            DrumKitPicker(kit: track.drumKit) { model.setDrumKit(index, $0) }
                .disabled(model.isRecording)
                .padding(.horizontal, 16)
        }
    }

    private var pads: some View {
        DrumPadGrid(kit: track.drumKit, settings: track.padSettings) { pad, lateBy in
            model.hitPad(pad, lateBy: lateBy)
        } onHold: { pad in
            guard !model.isRecording, !model.isSaving else { return }
            Hints.shared.dismiss(.padSound)
            editingPad = PadID(id: pad)
        }
        .padding(.horizontal, isWide ? 0 : 12)
        .frame(maxHeight: .infinity)
    }

    private var transportPanel: some View {
        VStack(spacing: 6) {
            if !model.isSimple {
                MetronomeBar(model: model)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }
            DrumTransport(model: model)
        }
        .glassPanel()
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Track controls

/// The armed drum track's header: a small handle centred at the very top,
/// then the name and M, S and Q (quantize). Swipe down anywhere on it (or tap
/// the handle) to put the pads away. The handle itself never moves: the swipe
/// is recognised, then one spring animation does the rest.
struct DrumTrackControls: View {
    @Bindable var model: ProjectViewModel
    let index: Int

    private var track: Track { model.project.tracks[index] }

    var body: some View {
        VStack(spacing: 0) {
            GrabberBar()
                .onTapGesture { hidePads() }
                .accessibilityElement()
                .accessibilityLabel("Hide drum pads")
                .accessibilityHint("Shows every track full size")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { hidePads() }
            HStack(spacing: 4) {
                Text(track.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ToggleChip(title: "M", isOn: track.mute, onColor: .orange, accessibilityName: "Mute \(track.name)") {
                    model.toggleMute(index)
                }
                ToggleChip(title: "S", isOn: track.solo, onColor: .yellow, accessibilityName: "Solo \(track.name)") {
                    model.toggleSolo(index)
                }
                QuantizeChip(model: model, index: index)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { g in
                    guard abs(g.translation.height) > abs(g.translation.width) else { return }
                    if g.translation.height > 20 || g.predictedEndTranslation.height > 70 { hidePads() }
                }
        )
    }

    private func hidePads() {
        guard !model.isRecording, !model.drumPadsHidden else { return }
        Haptics.slot.selectionChanged()
        withAnimation(PadsDrawer.animation) { model.drumPadsHidden = true }
    }
}

/// How the pads come and go: one smooth, slightly damped spring.
enum PadsDrawer {
    static let animation = Animation.spring(response: 0.42, dampingFraction: 0.92)
}

/// The iOS-style grabber: a short rounded bar with a generous, invisible hit area.
struct GrabberBar: View {
    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.45))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity, minHeight: 22)
            .contentShape(Rectangle())
    }
}

/// Q: tap to snap the drum track to the grid (at the current tempo) or back to
/// as played; press and hold to pick the grid.
struct QuantizeChip: View {
    @Bindable var model: ProjectViewModel
    let index: Int

    private var q: QuantizeSettings { model.project.tracks[index].quantize }

    var body: some View {
        Menu {
            Section("Quantize to") {
                ForEach(QuantizeDivision.menuOrder) { d in
                    Button {
                        model.setQuantizeDivision(index, d)
                    } label: {
                        if q.enabled && q.division == d {
                            Label(d.label, systemImage: "checkmark")
                        } else {
                            Text(d.label)
                        }
                    }
                }
            }
            Section("Strength") {
                ForEach(QuantizeSettings.strengths, id: \.self) { s in
                    Button {
                        model.setQuantizeStrength(index, s)
                    } label: {
                        let title = s == 1 ? "100% (exact)" : "\(Int(s * 100))% (keeps some feel)"
                        if q.enabled && abs(q.strength - s) < 0.001 {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
            if q.enabled {
                Button("Off (as played)") { model.toggleQuantize(index) }
            }
        } label: {
            Text(q.enabled ? "Q \(q.division.shortLabel)" : "Q")
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: q.enabled ? 56 : 40, height: 28)
                .foregroundStyle(q.enabled ? Color.black : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(q.enabled ? Color.green : Color(uiColor: .tertiarySystemFill))
                )
                .contentShape(Rectangle())
        } primaryAction: {
            model.toggleQuantize(index)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in Haptics.hold() })
        .disabled(model.isRecording || model.isSaving)
        .animation(.easeOut(duration: 0.15), value: q.enabled)
        .accessibilityLabel("Quantize")
        .accessibilityValue(q.enabled ? "On, \(q.division.label), \(Int(q.strength * 100)) percent" : "Off")
        .accessibilityHint("Tap to snap hits to the grid. Press and hold to choose the grid.")
    }
}

// MARK: - Kit choice

/// Studio / 808 / Hand Percussion, plus a Tight / Roomy switch under Studio.
struct DrumKitPicker: View {
    let kit: DrumKit
    let onChange: (DrumKit) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("Kit", selection: Binding(get: { kit.choice }, set: { onChange(kit.choosing($0)) })) {
                ForEach(DrumKit.kitChoices) { Text($0.familyName).tag($0) }
            }
            .pickerStyle(.segmented)

            if kit.isStudio {
                Picker("Studio sound", selection: Binding(get: { kit }, set: onChange)) {
                    ForEach(DrumKit.studioSounds) { Text($0.soundName ?? $0.familyName).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityHint("Tight is dry and punchy; Roomy keeps the sound of the room.")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: kit.isStudio)
    }
}

// MARK: - Pads

/// The pads. Each pad has its own UIKit touch area, so UIKit itself routes
/// every finger to the pad it landed on: no position bookkeeping that can drift
/// out of step with the layout. Fingers are tracked independently: a pad
/// sounds the instant a finger lands (also a second finger on a pad that's
/// already held, for rolls), sliding doesn't retrigger, and the touch's own
/// timestamp is passed on so recorded hits land where the finger did.
struct DrumPadGrid: View {
    let kit: DrumKit
    var settings: [PadSettings] = []
    /// A pad was hit; `lateBy` is how long ago the finger actually landed.
    let onHit: (Int, TimeInterval) -> Void
    var onHold: ((Int) -> Void)? = nil

    @State private var held: Set<Int> = []
    @State private var hits: [Int: Int] = [:]
    /// Shared by every pad: how many fingers are down anywhere on the grid.
    @State private var touches = PadTouches()

    static let spacing: CGFloat = 10

    var body: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(kit.padLayout.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.spacing) {
                    ForEach(row, id: \.self) { pad in
                        DrumPad(
                            name: kit.padNames[pad],
                            color: Self.color(kit.family(of: pad)),
                            isAdjusted: settings.indices.contains(pad) && !settings[pad].isDefault,
                            isHeld: held.contains(pad),
                            hitCount: hits[pad, default: 0],
                            onHit: { hit(pad, lateBy: 0) },
                            onHold: onHold.map { hold in { hold(pad) } }
                        )
                        // Half the gap on every side, so a finger between two
                        // pads still plays the nearer one.
                        .overlay(
                            PadTouchArea(
                                pad: pad,
                                touches: touches,
                                onDown: { lateBy in hit(pad, lateBy: lateBy) },
                                onUp: { held.remove(pad) },
                                onHold: onHold.map { hold in { hold(pad) } }
                            )
                            .padding(-Self.spacing / 2)
                            .accessibilityHidden(true)
                        )
                    }
                }
            }
        }
        .background(PopGestureBlocker().accessibilityHidden(true))
    }

    private func hit(_ pad: Int, lateBy: TimeInterval) {
        onHit(pad, lateBy)
        held.insert(pad)
        hits[pad, default: 0] += 1
    }

    /// Colour by what the pad is, the same in every kit: kicks red, snares and
    /// claps orange, hats and shakers yellow, toms purple, cymbals teal.
    static func color(_ family: DrumKit.PadFamily) -> Color {
        switch family {
        case .kick: return Color(red: 0.93, green: 0.30, blue: 0.33)
        case .snare: return Color(red: 0.98, green: 0.58, blue: 0.20)
        case .hat: return Color(red: 0.96, green: 0.78, blue: 0.18)
        case .tom: return Color(red: 0.58, green: 0.42, blue: 0.93)
        case .cymbal: return Color(red: 0.20, green: 0.72, blue: 0.78)
        case .accent: return Color(red: 0.30, green: 0.62, blue: 0.96)
        }
    }
}

/// One pad, drawing only (touch is handled by `PadTouchArea`): presses in
/// while held, flashes on every hit.
struct DrumPad: View {
    let name: String
    let color: Color
    var isAdjusted = false
    var isHeld = false
    /// Goes up by one on every hit, so each hit flashes, even repeated ones.
    var hitCount = 0
    /// For VoiceOver, which activates pads directly.
    let onHit: () -> Void
    var onHold: (() -> Void)? = nil
    @State private var lit = false

    /// UI tests launch with `-padHitCounts YES` to read each pad's hit count.
    private static let exposesHitCount = UserDefaults.standard.bool(forKey: "padHitCounts")

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape
            .fill(color.opacity(lit ? 0.95 : 0.22))
            .overlay(shape.strokeBorder(color.opacity(lit ? 1 : 0.55), lineWidth: 1.5))
            .overlay(alignment: .bottomLeading) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(lit ? .white : .primary)
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                if isAdjusted {
                    // This pad's sound has been adjusted.
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                        .padding(10)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 72, maxHeight: 150)
            .scaleEffect(isHeld ? 0.94 : 1)
            .animation(.spring(response: 0.16, dampingFraction: 0.6), value: isHeld)
            .onChange(of: hitCount) {
                // Light up at once, then fade; a new hit relights immediately.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { lit = true }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.28)) { lit = false }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue(Self.exposesHitCount ? "\(hitCount)" : (isAdjusted ? "Adjusted" : ""))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onHit() }
            .accessibilityAction(named: "Adjust sound") { onHold?() }
    }
}

/// Fingers down anywhere on the pad grid. Press-and-hold for a pad's settings
/// only counts when it's the only finger down, so resting a finger while
/// drumming never opens it; any new finger cancels a pending hold.
final class PadTouches {
    var fingers = 0
    private var pendingHold: DispatchWorkItem?

    func began(count: Int) {
        fingers += count
        cancelHold()
    }

    func ended(count: Int) {
        fingers = max(0, fingers - count)
        if fingers == 0 { cancelHold() }
    }

    func scheduleHold(_ work: DispatchWorkItem, after delay: TimeInterval) {
        cancelHold()
        pendingHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelHold() {
        pendingHold?.cancel()
        pendingHold = nil
    }
}

/// One pad's touch area.
struct PadTouchArea: UIViewRepresentable {
    let pad: Int
    let touches: PadTouches
    var onDown: (TimeInterval) -> Void
    var onUp: () -> Void
    var onHold: (() -> Void)?

    func makeUIView(context: Context) -> PadTouchView { PadTouchView(touches: touches) }

    func updateUIView(_ view: PadTouchView, context: Context) {
        view.pad = pad
        view.onDown = onDown
        view.onUp = onUp
        view.onHold = onHold
    }
}

final class PadTouchView: UIView {
    var pad = 0
    var onDown: (TimeInterval) -> Void = { _ in }
    var onUp: () -> Void = {}
    var onHold: (() -> Void)?

    private let touches: PadTouches
    /// Fingers on this pad, and where the one that may become a hold started.
    private var down: Set<ObjectIdentifier> = []
    private var holdStart: (id: ObjectIdentifier, point: CGPoint)?
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let holdHaptic = UIImpactFeedbackGenerator(style: .medium)

    static let holdDelay: TimeInterval = 0.55
    static let holdSlop: CGFloat = 16

    init(touches: PadTouches) {
        self.touches = touches
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func touchesBegan(_ set: Set<UITouch>, with event: UIEvent?) {
        let now = ProcessInfo.processInfo.systemUptime
        let wasIdle = touches.fingers == 0
        touches.began(count: set.count)
        holdStart = nil
        for touch in set {
            down.insert(ObjectIdentifier(touch))
            onDown(max(0, now - touch.timestamp))
        }
        haptic.impactOccurred()
        haptic.prepare()
        if onHold != nil, wasIdle, set.count == 1, let touch = set.first {
            let id = ObjectIdentifier(touch)
            holdStart = (id, touch.location(in: self))
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.touches.fingers == 1, self.holdStart?.id == id, self.down.contains(id) else { return }
                self.holdHaptic.impactOccurred()
                self.onHold?()
            }
            touches.scheduleHold(work, after: Self.holdDelay)
        }
    }

    override func touchesMoved(_ set: Set<UITouch>, with event: UIEvent?) {
        guard let start = holdStart, let touch = set.first(where: { ObjectIdentifier($0) == start.id }) else { return }
        let p = touch.location(in: self)
        if hypot(p.x - start.point.x, p.y - start.point.y) > Self.holdSlop {
            holdStart = nil
            touches.cancelHold()
        }
    }

    override func touchesEnded(_ set: Set<UITouch>, with event: UIEvent?) { lift(set) }
    override func touchesCancelled(_ set: Set<UITouch>, with event: UIEvent?) { lift(set) }

    private func lift(_ set: Set<UITouch>) {
        var lifted = 0
        for touch in set where down.remove(ObjectIdentifier(touch)) != nil {
            lifted += 1
            if holdStart?.id == ObjectIdentifier(touch) {
                holdStart = nil
                touches.cancelHold()
            }
        }
        touches.ended(count: lifted)
        // The pad stays pressed while another finger is still on it.
        if lifted > 0 && down.isEmpty { onUp() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            haptic.prepare()
        } else if !down.isEmpty {
            // Off screen mid-touch: release everything.
            touches.ended(count: down.count)
            down.removeAll()
            holdStart = nil
            onUp()
        }
    }
}

/// While the pads are on screen, the swipe-back edge gesture is off so the
/// left-hand pads respond instantly.
struct PopGestureBlocker: UIViewRepresentable {
    func makeUIView(context: Context) -> BlockerView { BlockerView() }
    func updateUIView(_ view: BlockerView, context: Context) {}

    final class BlockerView: UIView {
        private weak var gesture: UIGestureRecognizer?
        private var wasEnabled = true

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                if let g = navigationController?.interactivePopGestureRecognizer {
                    gesture = g
                    wasEnabled = g.isEnabled
                    g.isEnabled = false
                }
            } else {
                gesture?.isEnabled = wasEnabled
                gesture = nil
            }
        }

        private var navigationController: UINavigationController? {
            var responder: UIResponder? = self
            while let r = responder {
                if let vc = r as? UIViewController { return vc.navigationController }
                responder = r.next
            }
            return nil
        }
    }
}

// MARK: - Slim lanes

/// Every lane as one slim row: name, small waveform, armed dot. Tap a row to
/// arm it (an audio lane brings back the full recording view); drag sideways
/// to scrub; press and hold for Delete.
struct CompactLaneList: View {
    @Bindable var model: ProjectViewModel
    let onDeleteTrack: (Int) -> Void
    @State private var scrubStart: Double?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.visibleLanes, id: \.self) { i in
                row(i)
            }
            if model.visibleTrackCount < Project.trackCount {
                AddTrackButton(nextNumber: model.visibleTrackCount + 1, height: 34) { kind in model.addTrack(kind: kind) }
                    .disabled(model.isRecording || model.isSaving)
            }
        }
        .padding(.horizontal, 16)
    }

    private func row(_ i: Int) -> some View {
        let track = model.project.tracks[i]
        let armed = model.armedTrack == i
        let recordingHere = model.isRecording && armed
        return HStack(spacing: 10) {
            Image(systemName: track.isDrums ? "square.grid.2x2.fill" : "waveform")
                .font(.footnote)
                .foregroundStyle(armed ? Color.red : Color.secondary)
                .frame(width: 18)
            Text(track.name)
                .font(.subheadline.weight(armed ? .semibold : .regular))
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
            WaveformView(
                peaks: model.peaks[i],
                livePeaks: recordingHere ? model.livePeaks : [],
                liveStart: model.recordingStartSeconds,
                showsLive: recordingHere && !model.isCountingIn,
                clock: model.clock,
                anchor: model.isRecording ? 1 : 0.5,
                showsPlayheadLine: !model.isRecording,
                pointsPerSecond: WaveformView.defaultPointsPerSecond * model.effectiveZoom,
                color: model.project.isAudible(i) ? .primary : .secondary,
                beatGrid: model.beatGrid
            )
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(scrub)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.red.opacity(armed ? 0.8 : 0), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if !armed && !model.isRecording { Haptics.slot.selectionChanged() }
            model.arm(i)
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in Haptics.hold() })
        .contextMenu {
            if !model.isRecording {
                Button(role: .destructive) {
                    onDeleteTrack(i)
                } label: {
                    Label("Delete Track", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.name)\(armed ? ", armed" : "")")
        .accessibilityAddTraits(armed ? .isSelected : [])
        .accessibilityAction(named: "Arm for recording") { model.arm(i) }
    }

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                guard !model.isRecording, !model.isZooming, abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
                if scrubStart == nil {
                    scrubStart = model.playhead
                    model.beginScrub()
                }
                let before = model.playhead
                model.scrub(to: (scrubStart ?? 0) - Double(g.translation.width / (WaveformView.defaultPointsPerSecond * model.effectiveZoom)))
                Haptics.scrubTick(from: before, to: model.playhead, grid: model.beatGrid, end: model.duration)
            }
            .onEnded { _ in
                if scrubStart != nil {
                    scrubStart = nil
                    model.endScrub()
                }
            }
    }
}

// MARK: - Transport

/// One row: time, return to start, play, record, skip back. Record sits in
/// the middle under the pads so it's reachable without leaving the groove.
struct DrumTransport: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.isCountingIn ? "Count-in" : TimeFormat.precise(model.playhead))
                    .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.isRecording ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 92, alignment: .leading)
            .accessibilityElement(children: .combine)

            button("backward.end.fill", "Return to start") { model.returnToStart() }
                .disabled(model.isRecording)
            button(model.isPlaying || model.isRecording ? "pause.fill" : "play.fill",
                   model.isPlaying || model.isRecording ? "Pause" : "Play") { model.togglePlay() }
                .disabled(!model.hasAnyAudio && !model.isRecording)

            RecordButton(isRecording: model.isRecording, size: 60) { model.toggleRecord() }
                .frame(maxWidth: .infinity)

            button("gobackward.15", "Skip back 15 seconds") { model.skip(by: -15) }
                .disabled(model.isRecording)
        }
        .buttonStyle(.plain)
        .disabled(model.isSaving)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
