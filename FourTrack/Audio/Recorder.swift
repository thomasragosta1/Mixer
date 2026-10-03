import AVFoundation
import FourTrackCore


/// Receives input-tap buffers on the audio tap thread, converts them to the
/// 48 kHz mono working format, writes them to the scratch file and keeps a
/// live peak array for the waveform. Thread-safe: the tap thread writes,
/// the main thread reads snapshots.
final class RecordingSink: @unchecked Sendable {
    let url: URL
    private let writer: CAFWriter
    private var converter: AVAudioConverter?
    private let inputFormat: AVAudioFormat
    private let lock = NSLock()
    private var peaks = PeakAccumulator()
    private var firstHostTime: UInt64?
    private var failed = false
    private var finished = false

    init(url: URL, inputFormat: AVAudioFormat) throws {
        self.url = url
        self.inputFormat = inputFormat
        writer = try CAFWriter(url: url, sampleRate: EngineFormat.sampleRate)
        if inputFormat.sampleRate != EngineFormat.sampleRate || inputFormat.channelCount != 1 || inputFormat.commonFormat != .pcmFormatFloat32 {
            converter = AVAudioConverter(from: inputFormat, to: EngineFormat.mono)
        }
    }

    /// Called from the input tap.
    func append(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        lock.withLock {
            guard !finished, !failed else { return }
            if firstHostTime == nil {
                firstHostTime = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
            }
            guard let mono = convert(buffer), let data = mono.floatChannelData else { return }
            let samples = UnsafeBufferPointer(start: data[0], count: Int(mono.frameLength))
            do {
                try writer.write(samples)
                peaks.append(samples)
            } catch {
                failed = true
            }
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let ratio = EngineFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let out = AVAudioPCMBuffer(pcmFormat: EngineFormat.mono, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : out
    }

    /// Host time of the first captured sample, once audio has arrived.
    var firstSampleHostTime: UInt64? { lock.withLock { firstHostTime } }

    var framesWritten: Int64 { lock.withLock { writer.framesWritten } }

    /// Peaks captured so far, including the partially filled bucket.
    func livePeaks() -> [Float] {
        lock.withLock {
            var p = peaks.peaks
            if let pending = peaks.pending { p.append(pending) }
            return p
        }
    }

    /// Flushes and closes the scratch file. Safe to call more than once.
    func finish() throws {
        try lock.withLock {
            guard !finished else { return }
            finished = true
            try writer.finish()
        }
    }
}

/// Timing for one recording pass, captured when it starts.
struct RecordingPlan {
    let trackIndex: Int
    /// Timeline frame of the playhead when record was pressed.
    let startFrame: Int64
    /// Host time at which timeline `startFrame` is rendered by the players.
    let startHostTime: UInt64
    /// Round-trip compensation in seconds for the route in use.
    let latency: Double
    let route: AudioRouteKind
    let inputGainDB: Double

    /// Where the scratch recording goes on the timeline. The scratch file's
    /// frame 0 was captured at `firstSampleHost`; a sound the performer made
    /// in time with timeline `startFrame` arrives `latency` later, so we skip
    /// everything before that point.
    func placement(firstSampleHost: UInt64?) -> (skip: Int64, insert: Int64) {
        guard let firstSampleHost else {
            return (Int64((latency * EngineFormat.sampleRate).rounded()), startFrame)
        }
        let startSec = AVAudioTime.seconds(forHostTime: startHostTime)
        let firstSec = AVAudioTime.seconds(forHostTime: firstSampleHost)
        let offsetFrames = Int64(((startSec - firstSec + latency) * EngineFormat.sampleRate).rounded())
        if offsetFrames >= 0 {
            return (offsetFrames, startFrame)
        }
        // Capture began after the timeline start (should not happen, since the
        // tap is installed before playback starts): place it later instead.
        return (0, startFrame - offsetFrames)
    }
}
