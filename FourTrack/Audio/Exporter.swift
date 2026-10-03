import AVFoundation
import FourTrackCore

struct ExportOptions: Equatable {
    enum Format: String, CaseIterable, Identifiable {
        case aac = "AAC"
        case wav = "WAV"
        var id: String { rawValue }
        var fileExtension: String { self == .aac ? "m4a" : "wav" }
    }

    var format: Format = .aac
    var sampleRate: Double = 48_000

    static let standard = ExportOptions()
    static let sampleRates: [Double] = [44_100, 48_000]
}

enum ExportError: LocalizedError {
    case nothingToExport
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .nothingToExport: return "There's nothing recorded to export yet."
        case .renderFailed: return "The export couldn't be rendered."
        }
    }
}

/// Bounces a project offline through the same DSP graph as playback
/// (AVAudioEngine manual rendering), so the export sounds like the app.
enum Exporter {
    /// Seconds of extra render after the last sample, so reverb tails ring out.
    static let reverbTail = 2.0
    static let minimumTail = 0.1

    static func exportMix(project: Project, store: ProjectStore, options: ExportOptions, warmthEnabled: Bool, progress: @escaping @Sendable (Double) -> Void) throws -> URL {
        let url = destination(name: project.name, options: options)
        try render(project: project, store: store, tracks: Set(0..<Project.trackCount), soloTrack: nil, options: options, warmthEnabled: warmthEnabled, to: url, progress: progress)
        return url
    }

    static func exportTrack(_ index: Int, project: Project, store: ProjectStore, options: ExportOptions, warmthEnabled: Bool, progress: @escaping @Sendable (Double) -> Void) throws -> URL {
        let track = project.tracks[index]
        let url = destination(name: "\(project.name) - \(track.name)", options: options)
        try render(project: project, store: store, tracks: [index], soloTrack: index, options: options, warmthEnabled: warmthEnabled, to: url, progress: progress)
        return url
    }

    /// Developer Mode: every non-empty track as its own file.
    static func exportAllTracks(project: Project, store: ProjectStore, options: ExportOptions, warmthEnabled: Bool, progress: @escaping @Sendable (Double) -> Void) throws -> [URL] {
        let indices = project.tracks.filter { !$0.isEmpty }.map(\.index)
        guard !indices.isEmpty else { throw ExportError.nothingToExport }
        var urls: [URL] = []
        for (n, index) in indices.enumerated() {
            let base = Double(n) / Double(indices.count)
            let url = try exportTrack(index, project: project, store: store, options: options, warmthEnabled: warmthEnabled) { p in
                progress(base + p / Double(indices.count))
            }
            urls.append(url)
        }
        return urls
    }

    // MARK: Rendering

    /// - Parameters:
    ///   - tracks: which tracks to include.
    ///   - soloTrack: when set, that track is rendered "on its own" with its
    ///     processing and fader, ignoring mute and solo.
    private static func render(project: Project, store: ProjectStore, tracks: Set<Int>, soloTrack: Int?, options: ExportOptions, warmthEnabled: Bool, to url: URL, progress: (Double) -> Void) throws {
        let included = tracks.filter { !project.tracks[$0].isEmpty && (soloTrack != nil || project.isAudible($0)) }
        guard !included.isEmpty else { throw ExportError.nothingToExport }

        let engine = AVAudioEngine()
        let chains = (0..<Project.trackCount).map { TrackChain(index: $0) }
        let master = MasterChain()
        chains.forEach { $0.attach(to: engine) }
        master.attach(to: engine)
        chains.forEach { $0.connect(in: engine) }
        master.connect(tracks: chains, in: engine)

        guard let renderFormat = AVAudioFormat(standardFormatWithSampleRate: options.sampleRate, channels: 2) else {
            throw ExportError.renderFailed
        }
        try engine.enableManualRenderingMode(.offline, format: renderFormat, maximumFrameCount: 4096)

        var lengthSeconds = 0.0
        var hasSpace = false
        for chain in chains {
            let track = project.tracks[chain.index]
            if included.contains(chain.index) {
                let audio = track.audioFileName.map { store.fileURL($0, in: project.id) }
                let cleaned = track.cleanedFileName.map { store.fileURL($0, in: project.id) }
                chain.load(audioURL: audio, cleanedURL: cleaned)
                chain.apply(track, audible: true, warmthEnabled: warmthEnabled)
                lengthSeconds = max(lengthSeconds, Double(chain.lengthFrames) / EngineFormat.sampleRate)
                hasSpace = hasSpace || track.resolvedReverb.wetDryMix > 0
            } else {
                chain.apply(track, audible: false, warmthEnabled: warmthEnabled)
            }
        }
        master.apply(masterVolume: soloTrack == nil ? project.masterVolume : MacroCurves.volumeUnitySlider)

        try engine.start()
        defer { engine.stop() }
        for chain in chains where included.contains(chain.index) {
            if chain.schedule(from: 0) {
                chain.play(at: nil)
            }
        }

        let tail = hasSpace ? reverbTail : minimumTail
        let totalFrames = AVAudioFramePosition(((lengthSeconds + tail) * options.sampleRate).rounded())
        let file = try AVAudioFile(forWriting: url, settings: fileSettings(options), commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw ExportError.renderFailed
        }

        var lastReported = -1.0
        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = totalFrames - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
            switch try engine.renderOffline(frames, to: buffer) {
            case .success:
                try file.write(from: buffer)
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw ExportError.renderFailed
            @unknown default:
                throw ExportError.renderFailed
            }
            let p = Double(engine.manualRenderingSampleTime) / Double(totalFrames)
            if p - lastReported >= 0.01 {
                lastReported = p
                progress(min(1, p))
            }
        }
        progress(1)
    }

    private static func fileSettings(_ options: ExportOptions) -> [String: Any] {
        switch options.format {
        case .aac:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: options.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000,
            ]
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: options.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }
    }

    /// A fresh file in a per-export temporary folder, named after the project.
    private static func destination(name: String, options: ExportOptions) -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(sanitized(name)).appendingPathExtension(options.format.fileExtension)
    }

    static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Four-Track" : cleaned
    }

    /// Removes exports from earlier sessions.
    static func purgeOldExports() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }
}
