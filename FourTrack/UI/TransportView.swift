import SwiftUI
import FourTrackCore

/// Bottom transport: time readout, return to start, skip back/forward 15 s,
/// play/pause, and the big red record button.
struct TransportView: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        VStack(spacing: 10) {
            if !model.isSimple {
                MetronomeBar(model: model)
            }

            Text(model.isCountingIn ? "Count-in" : TimeFormat.precise(model.playhead))
                .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(model.isRecording ? .red : .primary)
                .accessibilityLabel(model.isRecording ? "Recording time" : "Playhead")
                .accessibilityValue(TimeFormat.duration(model.playhead))

            HStack(spacing: 0) {
                transportButton("backward.end.fill", label: "Return to start") { model.returnToStart() }
                transportButton("gobackward.15", label: "Skip back 15 seconds") { model.skip(by: -15) }
                Button {
                    model.togglePlay()
                } label: {
                    Image(systemName: model.isPlaying || model.isRecording ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(model.isPlaying || model.isRecording ? "Pause" : "Play")
                .disabled(!model.hasAnyAudio && !model.isRecording)
                transportButton("goforward.15", label: "Skip forward 15 seconds") { model.skip(by: 15) }
                Color.clear.frame(height: 44).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .disabled(model.isSaving)

            RecordButton(isRecording: model.isRecording) {
                model.toggleRecord()
            }
            .disabled(model.isSaving)
            .overlay(alignment: .trailing) {
                if model.isSaving {
                    ProgressView().offset(x: 56)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func transportButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(model.isRecording)
        .accessibilityLabel(label)
    }
}

/// Voice Memos-style record button: white ring, red circle that becomes a
/// rounded square while recording.
struct RecordButton: View {
    let isRecording: Bool
    var size: CGFloat = 80
    let action: () -> Void

    init(isRecording: Bool, size: CGFloat = 80, action: @escaping () -> Void) {
        self.isRecording = isRecording
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            let k = size / 80
            ZStack {
                Circle()
                    .strokeBorder(Color(uiColor: .systemGray3), lineWidth: 4 * k)
                    .frame(width: 72 * k, height: 72 * k)
                RoundedRectangle(cornerRadius: isRecording ? 8 * k : 29 * k, style: .continuous)
                    .fill(Color.red)
                    .frame(width: (isRecording ? 30 : 58) * k, height: (isRecording ? 30 : 58) * k)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecording)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }
}
