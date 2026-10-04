import XCTest
@testable import FourTrackCore

final class CompressorTests: XCTestCase {
    private func sine(db: Float, seconds: Double = 1, freq: Double = 1_000) -> [Float] {
        let amp = powf(10, db / 20)
        return (0..<Int(48_000 * seconds)).map { amp * Float(sin(2 * .pi * freq * Double($0) / 48_000)) }
    }

    private func peakDB(_ x: ArraySlice<Float>) -> Float {
        20 * log10f(max(x.map { abs($0) }.max() ?? 0, 1e-9))
    }

    func testStaticCurve() {
        let f = CompressorDSP.gainComputer
        // Well below threshold: unchanged.
        XCTAssertEqual(f(-40, -20, 4, 6), -40, accuracy: 1e-5)
        // Well above: threshold + over / ratio.
        XCTAssertEqual(f(0, -20, 4, 6), -15, accuracy: 1e-5)
        // Soft knee is continuous at both edges.
        XCTAssertEqual(f(-23, -20, 4, 6), -23, accuracy: 1e-4)
        XCTAssertEqual(f(-17, -20, 4, 6), -20 + 3 / 4, accuracy: 1e-4)
        // Hard knee.
        XCTAssertEqual(f(-10, -20, 2, 0), -15, accuracy: 1e-5)
    }

    func testZeroIsTransparent() {
        let input = sine(db: -3, seconds: 0.2)
        var out = input
        CompressorDSP(params: MacroCurves.compressor(0)).process(&out)
        XCTAssertEqual(out, input)
    }

    func testDefaultIsClearlyAudible() {
        // The owner's complaint: 30% did nothing. On a -10 dBFS tone it must now
        // take off several dB at the compressor stage.
        var x = sine(db: -10)
        let dsp = CompressorDSP(params: MacroCurves.compressor(Track.defaultCompressor))
        dsp.process(&x)
        let reduction = dsp.lastReductionDB
        XCTAssertGreaterThan(reduction, 4, "default compressor too gentle")
        XCTAssertLessThan(reduction, 9, "default compressor too heavy")
    }

    func testMoreSliderMeansMoreCompression() {
        // Dynamic range between a loud and a quiet section shrinks as the slider rises.
        var prevRange: Float = .infinity
        for slider in [0.0, 0.3, 0.6, 1.0] {
            var x = sine(db: -6, seconds: 0.5) + sine(db: -30, seconds: 0.5)
            CompressorDSP(params: MacroCurves.compressor(slider)).process(&x)
            let range = peakDB(x[12_000..<24_000]) - peakDB(x[36_000..<48_000])
            XCTAssertLessThan(range, prevRange, "slider \(slider)")
            prevRange = range
        }
        XCTAssertLessThan(prevRange, 12, "max setting should squash 24 dB of range to under 12")
    }

    func testSteadyStateNeverExceedsFullScale() {
        for i in 0...10 {
            let slider = Double(i) / 10
            for db: Float in [0, -6, -12, -20, -30] {
                var x = sine(db: db, seconds: 0.5, freq: 110)
                CompressorDSP(params: MacroCurves.compressor(slider)).process(&x)
                XCTAssertLessThanOrEqual(peakDB(x[12_000...]), 0.0, "slider \(slider) at \(db) dBFS")
                XCTAssertFalse(x.contains { !$0.isFinite })
            }
        }
    }

    func testStereoLinked() {
        var l = sine(db: -6, seconds: 0.3)
        var r = [Float](repeating: 0, count: l.count)
        let dsp = CompressorDSP(params: MacroCurves.compressor(0.8))
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                dsp.process(lp.baseAddress!, rp.baseAddress!, frames: lp.count)
            }
        }
        // Silent right channel stays silent; left is compressed.
        XCTAssertTrue(r.allSatisfy { $0 == 0 })
        XCTAssertLessThan(peakDB(l[7_200...]), -6)
    }

    func testOldOverridesDecode() throws {
        let json = #"{"thresholdDB":-18,"headroomDB":8,"attackSeconds":0.008,"releaseSeconds":0.12,"makeupGainDB":4}"#
        let p = try JSONDecoder().decode(CompressorParams.self, from: Data(json.utf8))
        XCTAssertEqual(p.ratio, 4)
        XCTAssertEqual(p.thresholdDB, -18)
    }
}
