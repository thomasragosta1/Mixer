import SwiftUI
import UIKit
import FourTrackCore

/// Record mode while a drum track is armed. The screen is rebuilt around
/// playing: the lanes shrink to slim rows (still tappable to switch tracks),
/// the pads take most of the screen, and the transport becomes one compact
/// row with a metronome right next to record.
struct DrumStudioView: View {
    @Bindable var model: ProjectViewModel
    let onDeleteTrack: (Int) -> Void
    @State private var showingMetronome = false

    private var index: Int { model.armedTrack }
    private var track: Track { model.project.tracks[index] }

    var body: some View {
        VStack(spacing: 10) {
            CompactLaneList(model: model, onDeleteTrack: onDeleteTrack)

            HStack(spacing: 10) {
                Picker("Kit", selection: Binding(get: { track.drumKit }, set: { model.setDrumKit(index, $0) })) {
                    ForEach(DrumKit.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isRecording)
            }
            .padding(.horizontal, 16)

            DrumPadGrid(kit: track.drumKit) { model.hitPad($0) }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)

            DrumTransport(model: model, showingMetronome: $showingMetronome)
                .glassPanel()
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .padding(.top, 2)
        .sheet(isPresented: $showingMetronome) {
            MetronomeSheet(model: model)
                .presentationDetents([.height(300)])
        }
    }
}

// MARK: - Pads

/// The 4 x 2 pad grid, laid out like a finger-drumming controller: kick,
/// snare and hats on the bottom row under the thumbs, toms and cymbals above.
/// Pads stretch to fill the space they're given.
struct DrumPadGrid: View {
    let kit: DrumKit
    let onHit: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(kit.padLayout.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { pad in
                        DrumPad(
                            name: kit.padNames[pad],
                            color: Self.color(kit.family(of: pad))
                        ) {
                            onHit(pad)
                        }
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
struct DrumPad: View {
    let name: String
    let color: Color
    let onHit: () -> Void
    @State private var pressed = false
    @State private var flash = false

    private static let haptic = UIImpactFeedbackGenerator(style: .light)

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
            .frame(minHeight: 72, maxHeight: 150)
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: pressed)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onHit()
                        Self.haptic.impactOccurred()
                        flash = true
                        withAnimation(.easeOut(duration: 0.3)) { flash = false }
                    }
                    .onEnded { _ in pressed = false }
            )
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onHit() }
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
                color: model.project.isAudible(i) ? .primary : .secondary
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
        .onTapGesture { model.arm(i) }
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
                model.scrub(to: (scrubStart ?? 0) - Double(g.translation.width / WaveformView.defaultPointsPerSecond))
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

/// One row: time, return to start, play, record, metronome. Record sits in
/// the middle under the pads so it's reachable without leaving the groove.
struct DrumTransport: View {
    @Bindable var model: ProjectViewModel
    @Binding var showingMetronome: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.isCountingIn ? "Count-in" : TimeFormat.precise(model.playhead))
                    .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.isRecording ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if model.project.metronome.enabled {
                    Text("\(Int(model.project.metronome.bpm)) BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

            Button {
                model.setMetronome { $0.enabled.toggle() }
            } label: {
                Image(systemName: "metronome.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(model.project.metronome.enabled ? Color.white : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(model.project.metronome.enabled ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in showingMetronome = true })
            .disabled(model.isRecording)
            .accessibilityLabel("Metronome")
            .accessibilityValue(model.project.metronome.enabled ? "On, \(Int(model.project.metronome.bpm)) BPM" : "Off")
            .accessibilityHint("Press and hold for tempo and count-in")
            .accessibilityAction(named: "Tempo and count-in") { showingMetronome = true }
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
