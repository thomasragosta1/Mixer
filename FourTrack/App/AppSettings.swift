import Foundation
import Observation
import FourTrackCore

/// App-wide preferences, persisted in UserDefaults.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    /// Reveals exploded controls, meters, metronome, latency tools and export options.
    var developerMode: Bool {
        didSet { defaults.set(developerMode, forKey: Keys.developerMode) }
    }

    /// Post-v1 feature flag for the Warmth macro. Hidden unless Developer Mode is on.
    var warmthEnabled: Bool {
        didSet { defaults.set(warmthEnabled, forKey: Keys.warmthEnabled) }
    }

    /// Recording through the iPhone speaker: Apple's echo cancellation keeps
    /// the playing tracks (and the click) out of the microphone. On by default.
    var speakerEchoCancellation: Bool {
        didSet { defaults.set(speakerEchoCancellation, forKey: Keys.speakerEchoCancellation) }
    }

    var latency: LatencySettings {
        didSet {
            if let data = try? JSONEncoder().encode(latency) {
                defaults.set(data, forKey: Keys.latency)
            }
        }
    }


    var exportFormat: ExportOptions.Format {
        didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) }
    }

    var exportSampleRate: Double {
        didSet { defaults.set(exportSampleRate, forKey: Keys.exportSampleRate) }
    }

    /// Export options in effect: Developer Mode choices, or the AAC default.
    var exportOptions: ExportOptions {
        developerMode ? ExportOptions(format: exportFormat, sampleRate: exportSampleRate) : .standard
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        developerMode = defaults.bool(forKey: Keys.developerMode)
        warmthEnabled = defaults.bool(forKey: Keys.warmthEnabled)
        speakerEchoCancellation = defaults.object(forKey: Keys.speakerEchoCancellation) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.latency), let decoded = try? JSONDecoder().decode(LatencySettings.self, from: data) {
            latency = decoded
        } else {
            latency = LatencySettings()
        }
        exportFormat = defaults.string(forKey: Keys.exportFormat).flatMap(ExportOptions.Format.init(rawValue:)) ?? .aac
        let rate = defaults.double(forKey: Keys.exportSampleRate)
        exportSampleRate = ExportOptions.sampleRates.contains(rate) ? rate : 48_000
    }

    private enum Keys {
        static let developerMode = "developerMode"
        static let warmthEnabled = "warmthEnabled"
        static let speakerEchoCancellation = "speakerEchoCancellation"
        static let latency = "latencySettings"
        static let exportFormat = "exportFormat"
        static let exportSampleRate = "exportSampleRate"
    }
}
