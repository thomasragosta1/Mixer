import SwiftUI
import FourTrackCore

/// One horizontal track lane in record mode: name, M/S, and a compact
/// waveform. Tapping the lane arms it.
struct TrackRowView: View {
    @Bindable var model: ProjectViewModel
    let index: Int
    @State private var renaming = false
    @State private var draftName = ""

    private var track: Track { model.project.tracks[index] }
    private var isArmed: Bool { model.armedTrack == index }
    private var isRecordingHere: Bool { model.isRecording && isArmed }

    var body: some View {
        HStack(spacing: 0) {
            controls
                .frame(width: 104, alignment: .leading)
                .padding(.leading, 12)
            WaveformView(
                peaks: model.peaks[index],
                livePeaks: isRecordingHere ? model.livePeaks : [],
                liveStart: model.recordingStartSeconds,
                showsLive: isRecordingHere && !model.isCountingIn,
                playhead: model.playhead,
                color: model.project.isAudible(index) ? .primary : .secondary
            )
            .overlay(alignment: .center) {
                if track.isEmpty && !isRecordingHere {
                    Text(isArmed ? "Ready to record" : "Empty")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isArmed ? Color.red.opacity(isRecordingHere ? 0.16 : 0.08) : Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isArmed ? Color.red.opacity(0.7) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.arm(index) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isArmed ? .isSelected : [])
        .accessibilityAction(named: "Arm for recording") { model.arm(index) }
        .alert("Rename Track", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.rename(track: index, to: draftName) }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                draftName = track.name
                renaming = true
            } label: {
                HStack(spacing: 4) {
                    if isArmed {
                        Circle().fill(Color.red).frame(width: 7, height: 7)
                    }
                    Text(track.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.name)\(isArmed ? ", armed" : "")")
            .accessibilityHint("Renames the track")

            HStack(spacing: 6) {
                ToggleChip(title: "M", isOn: track.mute, onColor: .orange, accessibilityName: "Mute \(track.name)") {
                    model.toggleMute(index)
                }
                ToggleChip(title: "S", isOn: track.solo, onColor: .yellow, accessibilityName: "Solo \(track.name)") {
                    model.toggleSolo(index)
                }
            }

            if let progress = model.cleanupProgress[index] {
                ProgressView(value: progress) {
                    Text("Cleaning up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
                .frame(width: 88)
            } else if !track.isEmpty {
                Text(TimeFormat.duration(track.durationSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
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
                .frame(width: 40, height: 32)
                .foregroundStyle(isOn ? Color.black : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? onColor : Color(uiColor: .tertiarySystemFill))
                )
                .contentShape(Rectangle())
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
