import XCTest
@testable import FourTrackCore

final class PadAndMetronomeTests: XCTestCase {
    private let tone: [Float] = (0..<24_000).map { i in Float(sin(2 * Double.pi * 220 * Double(i) / 48_000)) * expf(-Float(i) / 12_000) * 0.8 }

    func testDefaultPadSettingsLeaveSampleUntouched() {
        XCTAssertEqual(PadProcessor.apply(tone, .default), tone)
    }

    func testTuneChangesLengthLikeASampler() {
        let up = PadProcessor.apply(tone, PadSettings(tune: 1))      // +12 st
        let down = PadProcessor.apply(tone, PadSettings(tune: -1))   // -12 st
        XCTAssertEqual(Double(up.count), Double(tone.count) / 2, accuracy: 2)
        XCTAssertEqual(Double(down.count), Double(tone.count) * 2, accuracy: 2)
    }

    func testDecayShortensAndVolumeScales() {
        let short = PadProcessor.apply(tone, PadSettings(decay: 0))
        XCTAssertLessThan(short.count, tone.count / 2)
        XCTAssertEqual(short[0..<480].map(abs).max()!, tone[0..<480].map(abs).max()!, accuracy: 0.01, "attack must stay intact")
        let quiet = PadProcessor.apply(tone, PadSettings(volume: 0.5))
        XCTAssertLessThan(quiet.map(abs).max()!, tone.map(abs).max()! * 0.8)
        let muted = PadProcessor.apply(tone, PadSettings(volume: 0))
        XCTAssertEqual(muted.map(abs).max()!, 0, accuracy: 1e-6)
    }

    func testToneDarkensAndBrightens() {
        let noise: [Float] = (0..<9_600).map { _ in Float.random(in: -0.5...0.5) }
        func highEnergy(_ x: [Float]) -> Float {
            var hp = Biquad.highPass(frequency: 5_000, sampleRate: 48_000)
            return x.map { let y = hp.process($0); return y * y }.reduce(0, +)
        }
        XCTAssertLessThan(highEnergy(PadProcessor.apply(noise, PadSettings(tone: -1))), highEnergy(noise) * 0.2)
        XCTAssertGreaterThan(highEnergy(PadProcessor.apply(noise, PadSettings(tone: 1))), highEnergy(noise) * 3)
    }

    func testRenderUsesPadSettings() {
        let hits = [DrumHit(time: 0, pad: 0, velocity: 1)]
        var pads = Array(repeating: PadSettings.default, count: 8)
        let normal = DrumRenderer.render(hits, kit: .eightOhEight, pads: pads)
        pads[0].decay = 0
        let damped = DrumRenderer.render(hits, kit: .eightOhEight, pads: pads)
        XCTAssertLessThan(damped.count, normal.count)
    }

    func testTrackPadSettingsRoundTripAndPadToEight() throws {
        var t = Track(index: 0)
        XCTAssertEqual(t.padSettings.count, 8)
        t.padSettings[3] = PadSettings(volume: 0.5, tune: 0.25, decay: 0.4, tone: -0.3)
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.padSettings, t.padSettings)
        let old = try JSONDecoder().decode(Track.self, from: Data(#"{"index":0,"padSettings":[{"tune":0.5}]}"#.utf8))
        XCTAssertEqual(old.padSettings.count, 8)
        XCTAssertEqual(old.padSettings[0].tune, 0.5)
        XCTAssertEqual(old.padSettings[0].volume, MacroCurves.volumeUnitySlider)
    }

    func testMetronomeModesCycle() {
        XCTAssertEqual(MetronomeMode.off.next, .on)
        XCTAssertEqual(MetronomeMode.on.next, .visual)
        XCTAssertEqual(MetronomeMode.visual.next, .off)
        var m = MetronomeSettings()
        XCTAssertEqual(m.bpm, 120)
        XCTAssertEqual(m.tempoStep, 10)
        m.mode = .visual
        XCTAssertTrue(m.enabled, "visual-only still runs the beat grid")
    }

    func testTimeSignaturesCycleAndTempoNudges() {
        XCTAssertEqual(TimeSignature(4, 4).nextQuick, TimeSignature(3, 4))
        XCTAssertEqual(TimeSignature(3, 4).nextQuick, TimeSignature(2, 4))
        XCTAssertEqual(TimeSignature(2, 4).nextQuick, TimeSignature(4, 4))
        XCTAssertEqual(TimeSignature(7, 8).nextQuick, TimeSignature(4, 4))
        var m = MetronomeSettings()
        m.timeSignature = TimeSignature(6, 8)
        XCTAssertEqual(m.beatsPerBar, 6); XCTAssertEqual(m.beatUnit, 8)
        m.nudgeTempo(by: 10); XCTAssertEqual(m.bpm, 130)
        m.nudgeTempo(by: -1); XCTAssertEqual(m.bpm, 129)
        m.bpm = 235; m.nudgeTempo(by: 10); XCTAssertEqual(m.bpm, 240)
        m.bpm = 45; m.nudgeTempo(by: -10); XCTAssertEqual(m.bpm, 40)
    }

    func testBeatInBar() {
        var m = MetronomeSettings(); m.bpm = 120; m.beatsPerBar = 3
        XCTAssertEqual(m.beatInBar(at: 0), 0)
        XCTAssertEqual(m.beatInBar(at: 0.5), 1)
        XCTAssertEqual(m.beatInBar(at: 1.25), 2)
        XCTAssertEqual(m.beatInBar(at: 1.5), 0)
        XCTAssertEqual(m.beatInBar(at: -0.5), 2, "count-in beats before 0 stay on the grid")
    }

    func testOldMetronomeSettingsDecode() throws {
        let json = #"{"enabled":true,"bpm":92,"countInBars":2,"beatsPerBar":3,"volume":0.4}"#
        let m = try JSONDecoder().decode(MetronomeSettings.self, from: Data(json.utf8))
        XCTAssertEqual(m.mode, .on)
        XCTAssertEqual(m.bpm, 92)
        XCTAssertEqual(m.timeSignature, TimeSignature(3, 4))
        XCTAssertEqual(m.tempoStep, 10)
        var v = m; v.mode = .visual; v.tempoStep = 5
        XCTAssertEqual(try JSONDecoder().decode(MetronomeSettings.self, from: JSONEncoder().encode(v)), v)
    }
}

final class QuantizeTests: XCTestCase {
    func testSnapsToSixteenthsAtTempo() {
        // 120 BPM: quarter = 0.5 s, sixteenth = 0.125 s.
        let q = QuantizeSettings(enabled: true, division: .sixteenth, bpm: 120)
        XCTAssertEqual(q.gridSeconds, 0.125, accuracy: 1e-9)
        let hits = [DrumHit(time: 0.13, pad: 0), DrumHit(time: 0.49, pad: 1), DrumHit(time: 0.06, pad: 2)]
        let out = q.apply(to: hits)
        XCTAssertEqual(out.map(\.time), [0.0, 0.125, 0.5])
        XCTAssertEqual(out.map(\.pad), [2, 0, 1])
    }

    func testOffLeavesHitsAloneAndMergesDuplicates() {
        let hits = [DrumHit(time: 0.26, pad: 0, velocity: 0.5), DrumHit(time: 0.24, pad: 0, velocity: 0.9)]
        XCTAssertEqual(QuantizeSettings().apply(to: hits), hits)
        let q = QuantizeSettings(enabled: true, division: .eighth, bpm: 120)
        let out = q.apply(to: hits)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].velocity, 0.9)
        XCTAssertEqual(out[0].time, 0.25, accuracy: 1e-9)
    }

    func testEighthBeatUnitAndTriplets() {
        // 6/8 at 120 eighths per minute: an eighth = 0.5 s, so a quarter = 1 s.
        XCTAssertEqual(QuantizeSettings(enabled: true, division: .quarter, bpm: 120, beatUnit: 8).gridSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(QuantizeSettings(enabled: true, division: .eighthTriplet, bpm: 120).gridSeconds, 0.5 / 3, accuracy: 1e-9)
    }

    func testTrackRoundTripAndPlayableHits() throws {
        var t = Track(index: 0)
        t.kind = .drums
        t.drumHits = [DrumHit(time: 0.13, pad: 0)]
        XCTAssertEqual(t.playableDrumHits, t.drumHits)
        t.quantize = QuantizeSettings(enabled: true, division: .sixteenth, bpm: 120)
        XCTAssertEqual(t.playableDrumHits.map(\.time), [0.125])
        XCTAssertEqual(t.drumHits.map(\.time), [0.13], "original timing is kept")
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back.quantize, t.quantize)
    }
}
