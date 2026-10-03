import SwiftUI
import FourTrackCore

/// "Export Mix" or "Export Track…"; Developer Mode adds all-tracks export and
/// shows the chosen format. Results go to the system share sheet.
struct ExportSheet: View {
    @Bindable var model: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosingTrack = false

    var body: some View {
        NavigationStack {
            List {
                if let progress = model.exportProgress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Exporting…").font(.subheadline)
                            ProgressView(value: progress)
                        }
                        .padding(.vertical, 4)
                    }
                } else if choosingTrack {
                    Section("Choose a Track") {
                        ForEach(model.project.tracks) { track in
                            Button {
                                start(.track(track.index))
                            } label: {
                                HStack {
                                    Text(track.name)
                                    Spacer()
                                    Text(track.isEmpty ? "Empty" : TimeFormat.duration(track.durationSeconds))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .disabled(track.isEmpty)
                        }
                    }
                } else {
                    Section {
                        Button {
                            start(.mix)
                        } label: {
                            Label("Export Mix", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            choosingTrack = true
                        } label: {
                            Label("Export Track…", systemImage: "waveform")
                        }
                        if model.developerMode {
                            Button {
                                start(.allTracks)
                            } label: {
                                Label("Export All Tracks", systemImage: "square.stack.3d.up")
                            }
                        }
                    } footer: {
                        Text(formatDescription)
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if choosingTrack && model.exportProgress == nil {
                        Button("Back") { choosingTrack = false }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(model.exportProgress != nil)
                }
            }
        }
        .interactiveDismissDisabled(model.exportProgress != nil)
        .sheet(isPresented: Binding(
            get: { !model.exportedURLs.isEmpty },
            set: { presented in
                if !presented {
                    model.exportedURLs = []
                    dismiss()
                }
            }
        )) {
            ShareSheet(items: model.exportedURLs)
        }
    }

    private var formatDescription: String {
        let o = model.settings.exportOptions
        let rate = o.sampleRate == 44_100 ? "44.1 kHz" : "48 kHz"
        switch o.format {
        case .aac: return "AAC (.m4a), 256 kbps, \(rate)."
        case .wav: return "WAV, 24-bit, \(rate)."
        }
    }

    private func start(_ kind: ProjectViewModel.ExportKind) {
        model.export(kind)
    }
}
