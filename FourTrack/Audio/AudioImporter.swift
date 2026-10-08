import AVFoundation
import FourTrackCore

/// Turns any audio file iOS can read (Voice Memos .m4a, .wav, .mp3, .aiff,
/// .caf...) into a track file: 48 kHz mono Float32 CAF, written next to the
/// destination and then moved over it, so a failed import never leaves a
/// half-written track.
enum AudioImporter {
    enum ImportError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: "This file isn't audio Four-Track can read."
            case .empty: "This recording has no audio in it."
            }
        }
    }

    /// Converts `source` into `destination`. Returns the length in seconds.
    @discardableResult
    static func importAudio(from source: URL, to destination: URL) throws -> Double {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: source)
        } catch {
            throw ImportError.unreadable
        }
        guard file.length > 0 else { throw ImportError.empty }
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: CAFFormat.defaultSampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw ImportError.unreadable
        }
        // Stereo files fold down to one mono track instead of keeping the left side.
        converter.downmix = true
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue

        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".import-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: temp) }
        let writer = try CAFWriter(url: temp)

        let inChunk: AVAudioFrameCount = 16_384
        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let outChunk = AVAudioFrameCount(Double(inChunk) * ratio) + 1_024
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: inChunk),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outChunk) else {
            throw ImportError.unreadable
        }

        var readError: Error?
        var finished = false
        while true {
            outBuffer.frameLength = 0
            var convertError: NSError?
            let status = converter.convert(to: outBuffer, error: &convertError) { _, inputStatus in
                if finished || file.framePosition >= file.length {
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: inBuffer, frameCount: inChunk)
                } catch {
                    readError = error
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    finished = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let convertError { throw convertError }
            if let readError { throw readError }
            if outBuffer.frameLength > 0, let samples = outBuffer.floatChannelData?[0] {
                try writer.write(UnsafeBufferPointer(start: samples, count: Int(outBuffer.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }
        try writer.finish()
        guard writer.framesWritten > 0 else { throw ImportError.empty }
        try AtomicFile.replace(destination, with: temp)
        return Double(writer.framesWritten) / CAFFormat.defaultSampleRate
    }
}
