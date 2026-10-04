import SwiftUI
import FourTrackCore

/// Bottom transport: time readout, return to start, skip back/forward 15 s,
/// play/pause, and the big red record button.
struct TransportView: View {
    @Bindable var model: ProjectViewModel
    @State private var showingMetronome = false

    var body: some View {
        VStack(spacing: 10) {
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
                if model.developerMode {
                    metronomeButton
                } else {
                    Color.clear.frame(height: 44).frame(maxWidth: .infinity)
                }
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
        .sheet(isPresented: $showingMetronome) {
            MetronomeSheet(model: model)
                .presentationDetents([.height(300)])
        }
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

    /// Developer Mode: one visible toggle for the click; long press for tempo.
    private var metronomeButton: some View {
        Button {
            model.setMetronome { $0.enabled.toggle() }
        } label: {
            Image(systemName: "metronome")
                .font(.system(size: 22))
                .foregroundStyle(model.project.metronome.enabled ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .simultaneousGesture(LongPressGesture().onEnded { _ in showingMetronome = true })
        .accessibilityLabel("Metronome")
        .accessibilityValue(model.project.metronome.enabled ? "On, \(Int(model.project.metronome.bpm)) BPM" : "Off")
        .accessibilityAction(named: "Tempo and count-in") { showingMetronome = true }
    }
}

/// Voice Memos-style record button: white ring, red circle that becomes a
/// rounded square while recording.
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color(uiColor: .systemGray3), lineWidth: 4)
                    .frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 29, style: .continuous)
                    .fill(Color.red)
                    .frame(width: isRecording ? 30 : 58, height: isRecording ? 30 : 58)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isRecording)
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }
}

/// Tempo and count-in settings (Developer Mode).
struct MetronomeSheet: View {
    @Bindable var model: ProjectViewModel

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Click", isOn: Binding(
                    get: { model.project.metronome.enabled },
                    set: { v in model.setMetronome { $0.enabled = v } }
                ))
                Stepper(value: Binding(
                    get: { model.project.metronome.bpm },
                    set: { v in model.setMetronome { $0.bpm = min(max(v, MetronomeSettings.bpmRange.lowerBound), MetronomeSettings.bpmRange.upperBound) } }
                ), in: MetronomeSettings.bpmRange, step: 1) {
                    Text("Tempo: \(Int(model.project.metronome.bpm)) BPM")
                }
                Picker("Count-in", selection: Binding(
                    get: { model.project.metronome.countInBars },
                    set: { v in model.setMetronome { $0.countInBars = v } }
                )) {
                    Text("None").tag(0)
                    Text("1 bar").tag(1)
                    Text("2 bars").tag(2)
                }
                .pickerStyle(.segmented)
                Picker("Beats per bar", selection: Binding(
                    get: { model.project.metronome.beatsPerBar },
                    set: { v in model.setMetronome { $0.beatsPerBar = v } }
                )) {
                    ForEach([2, 3, 4, 6], id: \.self) { Text("\($0)").tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Click volume").font(.caption).foregroundStyle(.secondary)
                    MacroSlider(label: "Click volume", value: Binding(
                        get: { model.project.metronome.volume },
                        set: { v in model.setMetronome { $0.volume = v } }
                    ), defaultValue: 0.6)
                }
            }
            .navigationTitle("Metronome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
