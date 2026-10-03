import XCTest
@testable import FourTrackCore

final class DSPTests: XCTestCase {

    // MARK: Peaks

    func testPeaks() throws {
        var samples = [Float](repeating: 0, count: 1_000)
        samples[10] = -0.8
        samples[500] = 0.3
        samples[999] = 2 // clamps to 1
        let peaks = PeakGenerator.peaks(of: samples, framesPerPeak: 480)
        XCTAssertEqual(peaks, [0.8, 0.3, 1])
    }

    func testPeaksFromFileMatchInMemoryAndCacheRoundTrips() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = sine(frequency: 3, seconds: 2)
        let url = try writeCAF(s, to: dir.appendingPathComponent("a.caf"))
        let fromFile = try PeakGenerator.peaks(ofFileAt: url)
        XCTAssertEqual(fromFile, PeakGenerator.peaks(of: s))
        XCTAssertEqual(fromFile.count, 200)
        let cache = dir.appendingPathComponent("a.peaks")
        try PeakGenerator.write(fromFile, to: cache)
        XCTAssertEqual(try PeakGenerator.read(from: cache), fromFile)
    }

    func testPeakAccumulatorPending() {
        var acc = PeakAccumulator(framesPerPeak: 4)
        [Float(0.1), -0.5, 0.2].withUnsafeBufferPointer { acc.append($0) }
        XCTAssertEqual(acc.peaks, [])
        XCTAssertEqual(acc.pending, 0.5)
        [Float(0.0), 0.9].withUnsafeBufferPointer { acc.append($0) }
        XCTAssertEqual(acc.peaks, [0.5])
        XCTAssertEqual(acc.pending, 0.9)
    }

    // MARK: Latency calibration

    func testCalibrationFindsDelayThroughNoise() {
        let template = ClickTrack.click(accent: true)
        let delay = 1_234
        var rng = SeededRandom(seed: 7)
        var recorded = (0..<200_000).map { _ in rng.nextFloat() * 0.05 }
        let clicks = [10_000, 40_000, 70_000, 100_000, 130_000]
        for c in clicks {
            for (j, v) in template.enumerated() {
                recorded[c + delay + j] += v * 0.3
            }
        }
        let measured = LatencyCalibration.measureDelay(recorded: recorded, clickFrames: clicks, template: template, maxDelayFrames: 9_600)
        XCTAssertEqual(measured, delay)
    }

    func testCalibrationReturnsNilForSilence() {
        let template = ClickTrack.click(accent: true)
        let recorded = [Float](repeating: 0, count: 100_000)
        XCTAssertNil(LatencyCalibration.measureDelay(recorded: recorded, clickFrames: [1_000, 30_000], template: template, maxDelayFrames: 4_800))
    }

    // MARK: Click track

    func testBeatsGrid() {
        // 120 bpm at 48 kHz = 24,000 frames per beat.
        let beats = ClickTrack.beats(from: 0, to: 96_000, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(beats.map(\.frame), [0, 24_000, 48_000, 72_000])
        XCTAssertEqual(beats.map(\.accent), [true, false, false, false])
        let later = ClickTrack.beats(from: 30_000, to: 120_001, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(later.map(\.frame), [48_000, 72_000, 96_000, 120_000])
        XCTAssertEqual(later.map(\.accent), [false, false, true, false])
        XCTAssertEqual(ClickTrack.countInFrames(bars: 2, bpm: 120, beatsPerBar: 4), 192_000)
        XCTAssertEqual(ClickTrack.countInFrames(bars: 0, bpm: 120, beatsPerBar: 4), 0)
        // Count-in before timeline zero keeps the bar grid.
        let countIn = ClickTrack.beats(from: -96_000, to: 1, bpm: 120, beatsPerBar: 4)
        XCTAssertEqual(countIn.map(\.frame), [-96_000, -72_000, -48_000, -24_000, 0])
        XCTAssertEqual(countIn.map(\.accent), [true, false, false, false, true])
    }

    func testClickIsShortAndBounded() {
        let c = ClickTrack.click(accent: false)
        XCTAssertEqual(c.count, 1_440)
        XCTAssertLessThanOrEqual(c.map { abs($0) }.max()!, 1)
        XCTAssertEqual(c[0], 0)
    }

    // MARK: Cleanup stages

    func testDeEsserLeavesLowMaterialAlone() {
        var x = sine(frequency: 300, seconds: 0.5, amplitude: 0.5)
        let original = x
        var d = DeEsser(strength: 1)
        d.process(&x)
        // Only the tiny HPF leakage of a 300 Hz tone may be touched.
        XCTAssertEqual(rms(x), rms(original), accuracy: rms(original) * 0.02)
    }

    func testDeEsserReducesSibilance() {
        var rng = SeededRandom(seed: 3)
        // "Sss": noise high-passed at 6 kHz.
        var hp = Biquad.highPass(frequency: 6_000, sampleRate: 48_000)
        var x = (0..<24_000).map { _ in hp.process(rng.nextFloat() * 0.5) }
        let before = rms(x)
        var d = DeEsser(strength: 1)
        d.process(&x)
        let after = rms(x[4_800...])
        XCTAssertLessThan(after, before * 0.6)
        var off = DeEsser(strength: 0)
        var y = x
        off.process(&y)
        XCTAssertEqual(y, x)
    }

    func testTailSuppressorAttenuatesDecayButNotNotes() {
        // A loud note followed by a quiet decaying tail.
        let sr = 48_000.0
        var x: [Float] = []
        x += sine(frequency: 440, seconds: 0.5, amplitude: 0.8)
        let tail = sine(frequency: 440, seconds: 1.0, amplitude: 0.08)
        x += tail.enumerated().map { $0.element * Float(exp(-Double($0.offset) / sr * 2)) }
        let input = x
        var t = TailSuppressor(strength: 1)
        t.process(&x)
        let noteIn = rms(input[2_400..<24_000])
        let noteOut = rms(x[2_400..<24_000])
        XCTAssertEqual(noteOut, noteIn, accuracy: noteIn * 0.05)
        let tailIn = rms(input[40_000..<60_000])
        let tailOut = rms(x[40_000..<60_000])
        XCTAssertLessThan(tailOut, tailIn * 0.6)
    }

    // MARK: RNNoise pipeline

    func testRNNoiseFrameSize() {
        let p = RNNoiseProcessor()
        XCTAssertEqual(p.frameSize, 480)
    }

    func testRNNoiseLatencyIsOneFrame() {
        // A steady harmonic tone passes RNNoise largely intact; the best
        // alignment between input and output tells us the processor delay.
        let p = RNNoiseProcessor()
        let n = 48_000
        let input: [Float] = (0..<n).map { i in
            let t = Double(i) / 48_000
            let w = 2 * Double.pi * t
            let tone: Double = 0.3 * sin(220 * w) + 0.15 * sin(440 * w) + 0.1 * sin(660 * w)
            let wobble: Double = 1 + 0.5 * sin(3 * w)
            return Float(tone * wobble)
        }
        var output: [Float] = []
        var i = 0
        while i + 480 <= n {
            output += p.process(Array(input[i..<i + 480]))
            i += 480
        }
        var bestLag = 0
        var best = -Float.greatestFiniteMagnitude
        for lag in 0...1_000 {
            var dot: Float = 0
            for k in 10_000..<30_000 { dot += input[k] * output[k + lag] }
            if dot > best { best = dot; bestLag = lag }
        }
        // Band-gain smoothing adds a tiny phase shift on tonal material; the
        // pure processing delay is one frame.
        XCTAssertEqual(Double(bestLag), Double(p.latency), accuracy: 2)
    }

    func testCleanupPipelineReducesNoiseAndStaysAligned() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var rng = SeededRandom(seed: 11)
        let sr = 48_000.0
        // 1 s of noise only, then 2 s of a voiced tone over the same noise.
        let n = Int(3 * sr)
        // Room-like (low-passed, "brown") noise: RNNoise is trained on real
        // noise and barely touches synthetic white noise.
        var b: Float = 0
        let noise: [Float] = (0..<n).map { _ in
            b = 0.98 * b + rng.nextFloat() * 0.006
            return b
        }
        var signal = [Float](repeating: 0, count: n)
        for i in Int(sr)..<n {
            let w = 2 * Double.pi * Double(i) / sr
            let tone: Double = 0.25 * sin(200 * w) + 0.12 * sin(400 * w) + 0.06 * sin(800 * w)
            signal[i] = Float(tone)
        }
        let noisy = zip(signal, noise).map { $0 + $1 }
        let input = try writeCAF(noisy, to: dir.appendingPathComponent("in.caf"))
        let output = dir.appendingPathComponent("out.caf")
        var progressCalls: [Double] = []
        try CleanupPipeline().render(input: input, output: output, progress: { progressCalls.append($0) })
        let cleaned = try readCAF(output)

        XCTAssertEqual(cleaned.count, noisy.count)
        XCTAssertEqual(progressCalls.last ?? 0, 1, accuracy: 1e-9)
        // Noise-only section gets much quieter.
        let noiseBefore = rms(noisy[4_800..<43_200])
        let noiseAfter = rms(cleaned[4_800..<43_200])
        XCTAssertLessThan(noiseAfter, noiseBefore * 0.5)
        // Never clips.
        XCTAssertLessThanOrEqual(cleaned.map { abs($0) }.max() ?? 0, 1)
        // Output is time-aligned with the input: correlation peaks at lag 0.
        var bestLag = 0
        var best = -Float.greatestFiniteMagnitude
        for lag in -600...600 {
            var dot: Float = 0
            for k in 60_000..<120_000 { dot += noisy[k] * cleaned[k + lag] }
            if dot > best { best = dot; bestLag = lag }
        }
        // RNNoise's input high-pass adds a few samples of group delay at low
        // frequencies (a few degrees of phase at 200 Hz); the processing delay
        // itself is compensated exactly.
        XCTAssertLessThanOrEqual(abs(bestLag), 4, "cleaned take must line up with the original for blending")
    }

    func testCleanupCancellationKeepsNoOutput() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try writeCAF(sine(frequency: 200, seconds: 3), to: dir.appendingPathComponent("in.caf"))
        let output = dir.appendingPathComponent("out.caf")
        XCTAssertThrowsError(try CleanupPipeline().render(input: input, output: output, isCancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("cleanup") }
        XCTAssertEqual(leftovers, [])
    }
}
