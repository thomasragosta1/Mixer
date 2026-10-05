import SwiftUI
import FourTrackCore

/// One track as an iOS-style card: name, M/S and the Cleanup pill on the
/// left, waveform with the playhead on the right. Tap the card to arm it;
/// drag the waveform sideways to scrub.
struct TrackRowView<Scrub: Gesture>: View {
    @Bindable var model: ProjectViewModel
    let index: Int
    let onScrub: Scrub
    @State private var renaming = false
    @State private var draftName = ""

    static var cardHeight: CGFloat { 112 }

    private var track: Track { model.project.tracks[index] }
    private var isArmed: Bool { model.armedTrack == index }
    private var isRecordingHere: Bool { model.isRecording && isArmed }

    var body: some View {
        HStack(spacing: 12) {
            controls
                .frame(width: 92, alignment: .leading)
            waveform
        }
        .padding(12)
        .frame(height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color.red.opacity(isArmed ? 0.85 : 0), lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onTapGesture { arm() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isArmed ? .isSelected : [])
        .accessibilityAction(named: "Arm for recording") { model.arm(index) }
        .alert("Rename Track", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.rename(track: index, to: draftName) }
        }
    }

    private func arm() {
        if !isArmed && !model.isRecording { Haptics.slot.selectionChanged() }
        model.arm(index)
    }

    private var waveform: some View {
        WaveformView(
            peaks: model.peaks[index],
            livePeaks: isRecordingHere ? model.livePeaks : [],
            liveStart: model.recordingStartSeconds,
            showsLive: isRecordingHere && !model.isCountingIn,
            clock: model.clock,
            // All lanes share one anchor so they stay aligned: the right edge
            // while recording (newest audio enters from the right), the center
            // otherwise.
            anchor: model.isRecording ? 1 : 0.5,
            showsPlayheadLine: !model.isRecording,
            color: model.project.isAudible(index) ? .primary : .secondary,
            beatGrid: model.beatGrid
        )
        .overlay {
            if track.isEmpty && !isRecordingHere {
                Text(isArmed ? "Ready to record" : "Empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill).opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.innerRadius, style: .continuous))
        .contentShape(Rectangle())
        .gesture(onScrub)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tapping the name of another track arms it, like tapping anywhere
            // on its card; tapping the armed track's name renames it.
            Button {
                if isArmed {
                    draftName = track.name
                    renaming = true
                } else {
                    arm()
                }
            } label: {
                HStack(spacing: 5) {
                    if isArmed {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                    }
                    Text(track.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .frame(height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.name)\(isArmed ? ", armed" : "")")
            .accessibilityHint(isArmed ? "Renames the track" : "Arms the track for recording")

            if !model.isSimple {
                HStack(spacing: 6) {
                    ToggleChip(title: "M", isOn: track.mute, onColor: .orange, accessibilityName: "Mute \(track.name)") {
                        model.toggleMute(index)
                    }
                    ToggleChip(title: "S", isOn: track.solo, onColor: .yellow, accessibilityName: "Solo \(track.name)") {
                        model.toggleSolo(index)
                    }
                }
            }

            if track.isDrums && model.isSimple {
                Label("Drums", systemImage: "square.grid.3x2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if track.isDrums {
                KitMenu(kit: track.drumKit) { model.setDrumKit(index, $0) }
                    .disabled(model.isRecording)
            } else {
                CleanupToggle(
                    isOn: track.isCleanupOn,
                    progress: model.cleanupProgress[index],
                    trackName: track.name
                ) {
                    model.toggleCleanup(index)
                }
                .disabled(track.isEmpty || model.isRecording)
            }
        }
    }
}

/// Thin pill under M / S on drum tracks showing the kit; tap to change it.
struct KitMenu: View {
    let kit: DrumKit
    let onChange: (DrumKit) -> Void

    var body: some View {
        Menu {
            Picker("Kit", selection: Binding(get: { kit }, set: onChange)) {
                ForEach(DrumKit.menuOrder) { Text($0.displayName).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x2.fill")
                Text(kit.displayName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.primary)
            .frame(width: 86, height: 24)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drum kit")
        .accessibilityValue(kit.displayName)
    }
}

/// Long thin on/off button for Cleanup, under M / S. Shows render progress
/// while the cleaned copy is being made.
struct CleanupToggle: View {
    let isOn: Bool
    let progress: Double?
    let trackName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                if let progress, isOn {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: geo.size.width * progress)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text(progress != nil && isOn ? "Cleaning…" : "Clean up")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
            }
            .frame(width: 86, height: 24)
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clean up \(trackName)")
        .accessibilityValue(isOn ? (progress != nil ? "On, processing" : "On") : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The small M / S buttons. Large enough to hit with a thumb.
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    let onColor: Color
    let accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.bold))
                .frame(width: 40, height: 28)
                .foregroundStyle(isOn ? Color.black : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? onColor : Color(uiColor: .tertiarySystemFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
