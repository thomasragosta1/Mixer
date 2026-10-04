import XCTest
@testable import FourTrackCore

final class MacroCurvesTests: XCTestCase {

    // MARK: Volume

    func testVolumeAnchors() {
        XCTAssertEqual(MacroCurves.volumeDB(0), -.infinity)
        XCTAssertEqual(MacroCurves.volumeGain(0), 0)
        XCTAssertEqual(MacroCurves.volumeDB(0.75), 0, accuracy: 1e-9)
        XCTAssertEqual(MacroCurves.volumeGain(0.75), 1, accuracy: 1e-9)
        XCTAssertEqual(MacroCurves.volumeDB(1), 6, accuracy: 1e-9)
    }

    func testVolumeIsMonotonicAndClamped() {
        var last = -Double.infinity
        for i in 1...1000 {
            let db = MacroCurves.volumeDB(Double(i) / 1000)
            XCTAssertGreaterThan(db, last)
            last = db
        }
        XCTAssertEqual(MacroCurves.volumeDB(2), 6, accuracy: 1e-9)
        XCTAssertEqual(MacroCurves.volumeDB(-1), -.infinity)
        XCTAssertEqual(MacroCurves.volumeDB(.nan), -.infinity)
    }

    func testVolumeTaperIsAudioLike() {
        // Half way to unity should be well below -6 dB (audio taper, not linear).
        XCTAssertLessThan(MacroCurves.volumeDB(0.375), -12)
        XCTAssertGreaterThan(MacroCurves.volumeDB(0.375), -24)
    }

    func testVolumeInverseRoundTrips() {
        for s in stride(from: 0.01, through: 1.0, by: 0.01) {
            let back = MacroCurves.volumeSlider(forDB: MacroCurves.volumeDB(s))
            XCTAssertEqual(back, s, accuracy: 1e-9)
        }
        XCTAssertEqual(MacroCurves.volumeSlider(forDB: -.infinity), 0)
        XCTAssertEqual(MacroCurves.volumeSlider(forDB: 20), 1)
    }

    // MARK: EQ

    func testEQIsLinearAndClamped() {
        XCTAssertEqual(MacroCurves.eqGainDB(0), 0)
        XCTAssertEqual(MacroCurves.eqGainDB(1), 12)
        XCTAssertEqual(MacroCurves.eqGainDB(-1), -12)
        XCTAssertEqual(MacroCurves.eqGainDB(0.25), 3)
        XCTAssertEqual(MacroCurves.eqGainDB(5), 12)
        XCTAssertEqual(MacroCurves.eqSlider(forDB: 3), 0.25)
    }

    func testEQBands() {
        let bands = MacroCurves.eqBands(low: 0.5, mid: -0.5, high: 1)
        XCTAssertEqual(bands.map(\.kind), [.lowShelf, .parametric, .highShelf])
        XCTAssertEqual(bands.map(\.frequency), [120, 1_200, 8_000])
        XCTAssertEqual(bands.map(\.gainDB), [6, -6, 12])
        XCTAssertEqual(bands[1].bandwidthOctaves, 1.5)
    }

    // MARK: Compressor

    func testCompressorAnchors() {
        let off = MacroCurves.compressor(0)
        XCTAssertEqual(off, CompressorParams(thresholdDB: 0, ratio: 1, kneeDB: 6, attackSeconds: 0.010, releaseSeconds: 0.15, makeupGainDB: 0))
        let def = MacroCurves.compressor(0.3)
        XCTAssertEqual(def.thresholdDB, -20, accuracy: 1e-9)
        XCTAssertEqual(def.ratio, 2.5, accuracy: 1e-9)
        XCTAssertEqual(def.makeupGainDB, 4, accuracy: 1e-9)
        let max = MacroCurves.compressor(1)
        XCTAssertEqual(max.thresholdDB, -34, accuracy: 1e-9)
        XCTAssertEqual(max.ratio, 8, accuracy: 1e-9)
        XCTAssertEqual(max.attackSeconds, 0.002, accuracy: 1e-9)
        XCTAssertEqual(max.releaseSeconds, 0.07, accuracy: 1e-9)
        XCTAssertEqual(max.makeupGainDB, 11, accuracy: 1e-9)
    }

    func testCompressorInterpolatesAndIsMonotonic() {
        let a = MacroCurves.compressor(0.15)
        XCTAssertEqual(a.thresholdDB, -10, accuracy: 1e-9)
        XCTAssertEqual(a.ratio, 1.75, accuracy: 1e-9)
        var prev = MacroCurves.compressor(0)
        for i in 1...100 {
            let p = MacroCurves.compressor(Double(i) / 100)
            XCTAssertLessThanOrEqual(p.thresholdDB, prev.thresholdDB + 1e-9)
            XCTAssertGreaterThanOrEqual(p.ratio, prev.ratio - 1e-9)
            prev = p
        }
    }

    func testCompressorParamsStayInProcessorRanges() {
        for i in 0...100 {
            let p = MacroCurves.compressor(Double(i) / 100)
            XCTAssertTrue(CompressorParams.thresholdRange.contains(p.thresholdDB))
            XCTAssertTrue(CompressorParams.ratioRange.contains(p.ratio))
            XCTAssertTrue(CompressorParams.kneeRange.contains(p.kneeDB))
            XCTAssertTrue(CompressorParams.attackRange.contains(p.attackSeconds))
            XCTAssertTrue(CompressorParams.releaseRange.contains(p.releaseSeconds))
            XCTAssertTrue(CompressorParams.makeupRange.contains(p.makeupGainDB))
            // Makeup gain never exceeds the gain the threshold takes away at a full-scale peak,
            // so a 0 dBFS input cannot be pushed over full scale by the compressor alone.
            XCTAssertLessThanOrEqual(p.makeupGainDB, -p.thresholdDB + 1e-9)
        }
    }

    // MARK: Space

    func testSpaceCurve() {
        XCTAssertEqual(MacroCurves.spaceWetDryMix(0), 0)
        XCTAssertEqual(MacroCurves.spaceWetDryMix(1), 35)
        XCTAssertEqual(MacroCurves.spaceWetDryMix(0.5), 8.75, accuracy: 1e-9)
        XCTAssertEqual(MacroCurves.reverb(0.3).preset, .mediumRoom)
        XCTAssertLessThanOrEqual(MacroCurves.spaceWetDryMix(10), 35)
    }

    // MARK: Warmth

    func testWarmthTrimCompensatesDrive() {
        let w0 = MacroCurves.warmth(0)
        XCTAssertEqual(w0.wetDryMix, 0)
        XCTAssertEqual(w0.preGainDB, 0)
        XCTAssertEqual(w0.outputTrimDB, 0)
        let w1 = MacroCurves.warmth(1)
        XCTAssertEqual(w1.wetDryMix, 25)
        XCTAssertEqual(w1.preGainDB, 6)
        XCTAssertEqual(w1.outputTrimDB, -6)
        for i in 0...10 {
            let w = MacroCurves.warmth(Double(i) / 10)
            XCTAssertLessThanOrEqual(w.preGainDB + w.outputTrimDB, 3.0 + 1e-9)
        }
    }

    // MARK: Cleanup

    func testCleanupBlendSumsToUnity() {
        for i in 0...10 {
            let b = MacroCurves.cleanupBlend(Double(i) / 10)
            XCTAssertEqual(b.dry + b.wet, 1, accuracy: 1e-12)
        }
        XCTAssertEqual(MacroCurves.cleanupBlend(0).wet, 0)
        XCTAssertEqual(MacroCurves.cleanupBlend(1).dry, 0)
    }

    // MARK: Speech

    func testSpokenValues() {
        XCTAssertEqual(SliderSpeech.decibels(3.2), "plus 3 decibels")
        XCTAssertEqual(SliderSpeech.decibels(-6), "minus 6 decibels")
        XCTAssertEqual(SliderSpeech.decibels(0.2), "0 decibels")
        XCTAssertEqual(SliderSpeech.decibels(-.infinity), "silent")
        XCTAssertEqual(SliderSpeech.percent(0.4), "40 percent")
        XCTAssertEqual(SliderSpeech.shortDB(3), "+3.0 dB")
        XCTAssertEqual(SliderSpeech.shortDB(-2.25), "-2.3 dB")
        XCTAssertEqual(SliderSpeech.shortDB(0.01), "0 dB")
    }

    // MARK: Custom state

    func testDevOverridesMarkCustomOnlyWhenTheyDiffer() {
        var t = Track(index: 0)
        t.compressor = 0.5
        XCTAssertFalse(t.isCompressorCustom)
        t.devOverrides = DevParams(compressor: MacroCurves.compressor(0.5))
        XCTAssertFalse(t.isCompressorCustom)
        t.devOverrides?.compressor?.thresholdDB = -25
        XCTAssertTrue(t.isCompressorCustom)
        XCTAssertEqual(t.resolvedCompressor.thresholdDB, -25)

        t.devOverrides?.eq = MacroCurves.eqBands(low: 0, mid: 0, high: 0)
        XCTAssertFalse(t.isEQCustom)
        t.devOverrides?.eq?[1].frequency = 2_000
        XCTAssertTrue(t.isEQCustom)

        t.devOverrides?.reverb = ReverbParams(preset: .plate, wetDryMix: 0)
        XCTAssertTrue(t.isSpaceCustom)
    }
}
