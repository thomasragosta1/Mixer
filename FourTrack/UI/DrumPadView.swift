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
                    VStack(spacing: 10) {
                        hint
                        pads
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 10) {
                    CompactLaneList(model: model, onDeleteTrack: onDeleteTrack)
                    trackControls
                    hint
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

    // Pads always play, recording or not: jam along with the song first.
    private var hint: some View {
        Text(model.isRecording ? "Recording your hits" : (model.isPlaying ? "Playing along. Nothing records until you press ●" : "Play along anytime. Press ● to record"))
            .font(.caption)
            .foregroundStyle(model.isRecording ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var pads: some View {
        DrumPadGrid(kit: track.drumKit, settings: track.padSettings) {
            model.hitPad($0)
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

/// The armed drum track's name with M, S and Q (quantize).
struct DrumTrackControls: View {
    @Bindable var model: ProjectViewModel
    let index: Int

    private var track: Track { model.project.tracks[index] }

    var body: some View {
        HStack(spacing: 6) {
            Text(track.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            ToggleChip(title: "M", isOn: track.mute, onColor: .orange, accessibilityName: "Mute \(track.name)") {
                model.toggleMute(index)
            }
            ToggleChip(title: "S", isOn: track.solo, onColor: .yellow, accessibilityName: "Solo \(track.name)") {
                model.toggleSolo(index)
            }
            QuantizeChip(model: model, index: index)
        }
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
                .frame(width: q.enabled ? 64 : 40, height: 28)
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
struct DrumPadGrid: View {
    let kit: DrumKit
    var settings: [PadSettings] = []
    let onHit: (Int) -> Void
    var onHold: ((Int) -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(kit.padLayout.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { pad in
                        DrumPad(
                            name: kit.padNames[pad],
                            color: Self.color(kit.family(of: pad)),
                            isAdjusted: settings.indices.contains(pad) && !settings[pad].isDefault,
                            onHit: { onHit(pad) },
                            onHold: onHold.map { hold in { hold(pad) } }
                        )
                    }
                }
            }
        }
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

/// One pad. Fires on touch-down, lights up and gives a light haptic.
/// Pressing and holding (without sliding off) opens its sound settings.
struct DrumPad: View {
    let name: String
    let color: Color
    var isAdjusted = false
    let onHit: () -> Void
    var onHold: (() -> Void)? = nil
    @State private var pressed = false
    @State private var flash = false
    @State private var holdTask: Task<Void, Never>?

    private static let haptic = UIImpactFeedbackGenerator(style: .light)
    private static let holdHaptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        shape
            .fill(color.opacity(flash ? 0.95 : 0.22))
            .overlay(shape.strokeBorder(color.opacity(flash ? 1 : 0.55), lineWidth: 1.5))
            .overlay(alignment: .bottomLeading) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(flash ? .white : .primary)
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
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !pressed {
                            pressed = true
                            onHit()
                            Self.haptic.impactOccurred()
                            flash = true
                            withAnimation(.easeOut(duration: 0.3)) { flash = false }
                            if let onHold {
                                holdTask = Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 550_000_000)
                                    guard !Task.isCancelled else { return }
                                    Self.holdHaptic.impactOccurred()
                                    onHold()
                                }
                            }
                        } else if hypot(g.translation.width, g.translation.height) > 24 {
                            holdTask?.cancel()
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        holdTask?.cancel()
                        holdTask = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue(isAdjusted ? "Adjusted" : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onHit() }
            .accessibilityAction(named: "Adjust sound") { onHold?() }
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
