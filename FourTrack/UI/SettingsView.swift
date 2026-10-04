import SwiftUI
import FourTrackCore

/// App settings. Developer Mode lives here, off by default.
struct SettingsView: View {
    /// Present when opened from a project, for latency tools that need the engine.
    var model: ProjectViewModel?
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var calibrationResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Developer Mode", isOn: $settings.developerMode)
                } footer: {
                    Text("Shows detailed compressor, EQ and reverb controls, level meters, a metronome with count-in, latency tools and more export options. Turning it off hides them but keeps your values.")
                }

                if settings.developerMode {
                    latencySection
                    exportSection
                    Section {
                        Toggle("Echo Cancellation", isOn: $settings.voiceProcessing)
                    } header: {
                        Text("Speaker Overdubs")
                    } footer: {
                        Text("Uses Apple's voice processing to reduce backing-track bleed when recording without headphones. It changes the tone of the microphone; experimental. Applies from the next recording.")
                    }
                    Section {
                        Toggle("Warmth Macro", isOn: $settings.warmthEnabled)
                    } header: {
                        Text("Experimental")
                    } footer: {
                        Text("Adds a Warmth slider (gentle saturation) to each channel strip.")
                    }
                }

                Section {
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var latencySection: some View {
        let route = model?.currentRoute ?? AudioSessionManager.shared.currentRoute
        let manual = Binding(
            get: { settings.latency.manualOffsetMs[route] ?? 0 },
            set: { settings.latency.manualOffsetMs[route] = ($0 * 2).rounded() / 2 }
        )
        return Section {
            LabeledContent("Route", value: route.displayName)
            if let measured = settings.latency.measured[route] {
                LabeledContent("Calibrated", value: String(format: "%.1f ms", measured * 1000))
            } else if let model {
                LabeledContent("Estimated", value: String(format: "%.1f ms", model.estimatedLatencyMs))
            }
            ParamSlider(
                title: "Manual offset",
                value: manual.wrappedValue,
                range: LatencySettings.manualRangeMs,
                centered: true,
                format: { String(format: "%+.1f ms", $0) },
                resetValue: 0
            ) { manual.wrappedValue = $0 }
            if let model {
                Button {
                    Task { calibrationResult = await model.calibrateLatency() }
                } label: {
                    HStack {
                        Text("Calibrate")
                        if model.isCalibrating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.isCalibrating || model.isRecording)
            }
            if let calibrationResult {
                Text(calibrationResult).font(.footnote).foregroundStyle(.secondary)
            }
            if settings.latency.measured[route] != nil {
                Button("Clear Calibration", role: .destructive) {
                    settings.latency.measured[route] = nil
                }
            }
        } header: {
            Text("Recording Latency")
        } footer: {
            Text("Calibrate plays a few clicks and listens for them. On the speaker it just works; with headphones, hold an earbud next to the microphone. Positive offsets move new takes earlier.")
        }
    }

    private var exportSection: some View {
        Section("Export") {
            Picker("Format", selection: $settings.exportFormat) {
                ForEach(ExportOptions.Format.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Sample Rate", selection: $settings.exportSampleRate) {
                Text("44.1 kHz").tag(44_100.0)
                Text("48 kHz").tag(48_000.0)
            }
        }
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Drum Samples").font(.headline)
                Text(Acknowledgements.samples)
                    .font(.footnote)
                Text("RNNoise").font(.headline)
                Text(Acknowledgements.rnnoise)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
