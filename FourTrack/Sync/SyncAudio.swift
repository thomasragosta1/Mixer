import AVFoundation
import FourTrackCore

/// Audio as it travels through iCloud: Apple Lossless (about half the size of
/// the app's 32-bit float files, bit-exact at 24 bits). A take with samples
/// beyond full scale, which 24-bit can't hold, travels as the original CAF.
enum SyncAudio {
    /// Writes the upload copy of `source` next to `base` and returns it:
    /// `base.m4a` (Apple Lossless) or `base.caf`.
    static func stage(_ source: URL, as base: URL) throws -> URL {
        let alac = base.appendingPathExtension("m4a")
        let raw = base.appendingPathExtension("caf")
        let fm = FileManager.default
        try? fm.removeItem(at: alac)
        try? fm.removeItem(at: raw)
        if try writeLossless(source, to: alac) { return alac }
        try? fm.removeItem(at: alac)
        try fm.copyItem(at: source, to: raw)
        return raw
    }

    /// False when the take can't be held losslessly in 24 bits.
    private static func writeLossless(_ source: URL, to url: URL) throws -> Bool {
        let input = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard input.length > 0, input.processingFormat.channelCount == 1 else { return false }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: input.processingFormat.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitDepthHintKey: 24,
        ]
        let chunk: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: chunk) else { return false }
        // Scoped so the file is closed (and complete) before it's uploaded.
        do {
            let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            while input.framePosition < input.length {
                try input.read(into: buffer, frameCount: min(chunk, AVAudioFrameCount(input.length - input.framePosition)))
                guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { break }
                for i in 0..<Int(buffer.frameLength) where abs(samples[i]) > 1 { return false }
                try output.write(from: buffer)
            }
        }
        return true
    }

    /// Turns a downloaded copy back into a track file at `destination`.
    static func restore(_ staged: URL, to destination: URL) throws {
        if staged.pathExtension == "caf" {
            let reader = try CAFReader(url: staged)
            guard reader.sampleRate == CAFFormat.defaultSampleRate, reader.channelCount == 1 else { throw AudioImporter.ImportError.unreadable }
            let temp = destination.deletingLastPathComponent().appendingPathComponent(".sync-\(UUID().uuidString).caf")
            try FileManager.default.copyItem(at: staged, to: temp)
            try AtomicFile.replace(destination, with: temp)
        } else {
            try AudioImporter.importAudio(from: staged, to: destination)
        }
    }
}
