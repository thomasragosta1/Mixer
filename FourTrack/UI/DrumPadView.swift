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

/// The 4 x 2 pad grid, laid out like a finger-drumming controller: kick,
/// snare and hats on the bottom row under the thumbs, toms and cymbals above.
/// Pads stretch to fill the space they're given.
///
/// Touch goes through one UIKit surface over the whole grid (`PadTouchSurface`)
/// rather than a SwiftUI gesture per pad: every finger is tracked on its own,
/// a pad sounds the instant a finger lands (also a second finger on a pad
/// that's already held, for rolls), and the touch's own timestamp is passed on
/// so recorded hits land where the finger did. The pads themselves only draw.
struct DrumPadGrid: View {
    let kit: DrumKit
    var settings: [PadSettings] = []
    /// A pad was hit; `lateBy` is how long ago the finger actually landed.
    let onHit: (Int, TimeInterval) -> Void
    var onHold: ((Int) -> Void)? = nil

    @State private var frames: [Int: CGRect] = [:]
    @State private var held: Set<Int> = []
    @State private var hits: [Int: Int] = [:]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(kit.padLayout.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { pad in
                        DrumPad(
                            name: kit.padNames[pad],
                            color: Self.color(kit.family(of: pad)),
                            isAdjusted: settings.indices.contains(pad) && !settings[pad].isDefault,
                            isHeld: held.contains(pad),
                            hitCount: hits[pad, default: 0],
                            onHit: { onHit(pad, 0) },
                            onHold: onHold.map { hold in { hold(pad) } }
                        )
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("pads")) }) { frames[pad] = $0 }
                    }
                }
            }
        }
        .coordinateSpace(.named("pads"))
        .overlay(
            PadTouchSurface(
                frames: frames,
                onDown: { pad, lateBy in
                    onHit(pad, lateBy)
                    held.insert(pad)
                    hits[pad, default: 0] += 1
                },
                onUp: { pad in held.remove(pad) },
                onHold: onHold
            )
        )
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

/// One pad, drawing only (touch is handled by `PadTouchSurface`): presses in
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
            .accessibilityValue(isAdjusted ? "Adjusted" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onHit() }
            .accessibilityAction(named: "Adjust sound") { onHold?() }
    }
}

/// One touch surface over the whole pad grid. Each finger is tracked on its
/// own: a pad sounds the moment a finger lands on it (a second finger on a
/// held pad hits again), sliding doesn't retrigger, and lifting releases it.
/// A press-and-hold opens the pad's settings only when it's the only finger
/// down and it hasn't moved, so resting a finger while drumming never does.
/// While it's on screen, the swipe-back edge gesture is switched off so the
/// left-hand pads respond instantly.
struct PadTouchSurface: UIViewRepresentable {
    var frames: [Int: CGRect]
    var onDown: (Int, TimeInterval) -> Void
    var onUp: (Int) -> Void
    var onHold: ((Int) -> Void)?

    func makeUIView(context: Context) -> PadTouchView { PadTouchView() }

    func updateUIView(_ view: PadTouchView, context: Context) {
        view.frames = frames
        view.onDown = onDown
        view.onUp = onUp
        view.onHold = onHold
    }
}

final class PadTouchView: UIView {
    var frames: [Int: CGRect] = [:]
    var onDown: (Int, TimeInterval) -> Void = { _, _ in }
    var onUp: (Int) -> Void = { _ in }
    var onHold: ((Int) -> Void)?

    private struct Finger {
        let pad: Int
        let start: CGPoint
        var hold: DispatchWorkItem?
    }

    private var fingers: [ObjectIdentifier: Finger] = [:]
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let holdHaptic = UIImpactFeedbackGenerator(style: .medium)
    private weak var popGesture: UIGestureRecognizer?
    private var popWasEnabled = true

    static let holdDelay: TimeInterval = 0.55
    static let holdSlop: CGFloat = 16

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The pad under a point; the gaps between pads go to the nearest one.
    private func pad(at point: CGPoint) -> Int? {
        if let hit = frames.first(where: { $0.value.insetBy(dx: -5, dy: -5).contains(point) }) { return hit.key }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = ProcessInfo.processInfo.systemUptime
        // Any new finger means the player is drumming: no settings bubble.
        cancelHolds()
        for touch in touches {
            let point = touch.location(in: self)
            guard let pad = pad(at: point) else { continue }
            var finger = Finger(pad: pad, start: point, hold: nil)
            onDown(pad, max(0, now - touch.timestamp))
            haptic.impactOccurred()
            if onHold != nil, fingers.isEmpty, touches.count == 1 {
                let id = ObjectIdentifier(touch)
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.fingers.count == 1, self.fingers[id]?.pad == pad else { return }
                    self.holdHaptic.impactOccurred()
                    self.onHold?(pad)
                }
                finger.hold = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
            }
            fingers[ObjectIdentifier(touch)] = finger
        }
        haptic.prepare()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let finger = fingers[id], finger.hold != nil else { continue }
            let p = touch.location(in: self)
            if hypot(p.x - finger.start.x, p.y - finger.start.y) > Self.holdSlop {
                finger.hold?.cancel()
                fingers[id]?.hold = nil
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let finger = fingers.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            finger.hold?.cancel()
            // The pad stays pressed while another finger is still on it.
            if !fingers.values.contains(where: { $0.pad == finger.pad }) { onUp(finger.pad) }
        }
    }

    private func cancelHolds() {
        for (id, finger) in fingers where finger.hold != nil {
            finger.hold?.cancel()
            fingers[id]?.hold = nil
        }
    }

    // MARK: Swipe-back edge gesture

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            haptic.prepare()
            if let gesture = navigationController?.interactivePopGestureRecognizer {
                popGesture = gesture
                popWasEnabled = gesture.isEnabled
                gesture.isEnabled = false
            }
        } else {
            popGesture?.isEnabled = popWasEnabled
            popGesture = nil
            // Off screen mid-touch: release everything.
            for (_, finger) in fingers { finger.hold?.cancel(); onUp(finger.pad) }
            fingers.removeAll()
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
                pointsPerSecond: WaveformView.defaultPointsPerSecond,
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
                guard !model.isRecording, abs(g.translation.width) > abs(g.translation.height) || scrubStart != nil else { return }
                if scrubStart == nil {
                    scrubStart = model.playhead
                    model.beginScrub()
                }
                let before = model.playhead
                model.scrub(to: (scrubStart ?? 0) - Double(g.translation.width / WaveformView.defaultPointsPerSecond))
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
