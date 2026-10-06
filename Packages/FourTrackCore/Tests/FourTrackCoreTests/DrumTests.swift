import XCTest
@testable import FourTrackCore

final class DrumTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        // The samples live in the app's resources: <repo>/FourTrack/Resources/Drums.
        DrumSamples.directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("FourTrack/Resources/Drums")
    }

    func testMissingSamplesFallBackToSynthesis() {
        let saved = DrumSamples.directory
        DrumSamples.directory = URL(fileURLWithPath: "/nonexistent")
        defer { DrumSamples.directory = saved }
        XCTAssertGreaterThan(DrumKit.studio.sample(pad: 0).count, 1_000)
    }
    func testEveryPadOfEveryKitRendersCleanly() {
        for kit in DrumKit.allCases {
            XCTAssertEqual(kit.padNames.count, DrumKit.padCount)
            for pad in 0..<DrumKit.padCount {
              for variant in 0..<kit.variantCount {
                let s = kit.sample(pad: pad, variant: variant)
                XCTAssertGreaterThan(s.count, 1_000, "\(kit) pad \(pad) too short")
                XCTAssertLessThan(s.count, 48_000 * 4, "\(kit) pad \(pad) too long")
                let peak = s.map { abs($0) }.max() ?? 0
                XCTAssertEqual(peak, 0.89, accuracy: 0.001, "\(kit) pad \(pad) not normalized")
                XCTAssertFalse(s.contains { $0.isNaN || $0.isInfinite })
                XCTAssertLessThan(abs(s.last ?? 1), 0.01, "\(kit) pad \(pad) ends with a click")
                // Pads must speak immediately: loud within the first 5 ms.
                let attack = s.prefix(240).map { abs($0) }.max() ?? 0
                XCTAssertGreaterThan(attack, 0.1, "\(kit) pad \(pad) v\(variant) attack is late")
              }
            }
        }
    }

    func testPadLayoutUsesEveryPadOnceWithGrooveOnTheBottomRow() {
        for kit in DrumKit.allCases {
            let flat = kit.padLayout.flatMap { $0 }
            XCTAssertEqual(flat.sorted(), Array(0..<DrumKit.padCount), "\(kit)")
            XCTAssertEqual(kit.padLayout.count, 2)
            let bottom = kit.padLayout[1]
            XCTAssertEqual(kit.family(of: bottom[0]), .kick, "\(kit) kick bottom-left")
            XCTAssertEqual(kit.family(of: bottom[1]), .snare, "\(kit) snare next to kick")
        }
    }

    func testStudioSounds() {
        // Existing tracks keep the original Studio kit; it is now the "Roomy" sound.
        XCTAssertEqual(DrumKit(rawValue: "studio"), .studio)
        XCTAssertEqual(DrumKit.studio.displayName, "Studio · Roomy")
        XCTAssertEqual(DrumKit.studioTight.displayName, "Studio · Tight")
        XCTAssertEqual(DrumKit.eightOhEight.displayName, "808")
        XCTAssertEqual(Track(index: 0).drumKit, .studioTight)
        // Picking "Studio" keeps the current Studio sound, or starts on Tight.
        XCTAssertEqual(DrumKit.studio.choosing(.studio), .studio)
        XCTAssertEqual(DrumKit.eightOhEight.choosing(.studio), .studioTight)
        XCTAssertEqual(DrumKit.studioTight.choosing(.handPercussion), .handPercussion)
        XCTAssertEqual(Set(DrumKit.menuOrder), Set(DrumKit.allCases))
        XCTAssertEqual(DrumKit.studioTight.choice, .studio)
        // Tight really is tighter: every drum (not cymbal) pad is shorter than its Roomy twin.
        for pad in [0, 1, 2, 4, 5] {
            XCTAssertLessThan(DrumKit.studioTight.sample(pad: pad).count, DrumKit.studio.sample(pad: pad).count, "pad \(pad)")
        }
        // A kit this version doesn't know decodes to the default instead of failing the project.
        let json = #"{"index":1,"kind":"drums","drumKit":"someFutureKit"}"#
        XCTAssertEqual(try JSONDecoder().decode(Track.self, from: Data(json.utf8)).drumKit, .studioTight)
    }

    func testKitsSoundDifferent() {
        // Same pad slot across kits must not be near-identical.
        for pad in 0..<DrumKit.padCount {
            let a = DrumKit.studio.sample(pad: pad)
            let b = DrumKit.eightOhEight.sample(pad: pad)
            let c = DrumKit.handPercussion.sample(pad: pad)
            XCTAssertLessThan(abs(correlation(a, b)), 0.9, "pad \(pad) studio vs 808")
            XCTAssertLessThan(abs(correlation(a, c)), 0.9, "pad \(pad) studio vs hand")
            XCTAssertLessThan(abs(correlation(b, c)), 0.9, "pad \(pad) 808 vs hand")
        }
    }

    func testSampledKitsLoadRealSamplesAndAlternateTakes() {
        for kit in [DrumKit.studio, .studioTight, .handPercussion] {
            XCTAssertNotNil(DrumSamples.load(kit: kit, pad: 0, variant: 0, sampleRate: 48_000), "\(kit) samples missing from bundle")
            for pad in 0..<DrumKit.padCount {
                let a = kit.sample(pad: pad, variant: 0)
                let b = kit.sample(pad: pad, variant: 1)
                XCTAssertNotEqual(a, b, "\(kit) pad \(pad) takes identical")
            }
        }
        // Two quick kicks render two different takes.
        let out = DrumRenderer.render([DrumHit(time: 0, pad: 0, velocity: 1), DrumHit(time: 1, pad: 0, velocity: 1)], kit: .studio)
        XCTAssertNotEqual(Array(out[0..<4_800]), Array(out[48_000..<52_800]))
        // Resampled renders keep their length ratio.
        let r = DrumKit.studio.sample(pad: 0, sampleRate: 44_100)
        XCTAssertEqual(Double(r.count), Double(DrumKit.studio.sample(pad: 0).count) * 44_100 / 48_000, accuracy: 2)
    }

    func testRenderPlacesHitsAtTheirTimes() {
        let hits = [DrumHit(time: 0.5, pad: 0, velocity: 1), DrumHit(time: 1.0, pad: 1, velocity: 1)]
        let out = DrumRenderer.render(hits, kit: .studio)
        XCTAssertTrue(out[0..<23_990].allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(out[24_000..<24_480].map { abs($0) }.max()!, 0.1)
        XCTAssertGreaterThan(out.count, 48_000)
        XCTAssertLessThanOrEqual(out.map { abs($0) }.max()!, 1)
    }

    func testDensePatternNeverClips() {
        let hits = (0..<200).map { DrumHit(time: Double($0) * 0.01, pad: $0 % 8, velocity: 1) }
        let out = DrumRenderer.render(hits, kit: .eightOhEight)
        XCTAssertLessThanOrEqual(out.map { abs($0) }.max()!, 1.0)
    }

    func testOverwriteReplacesOnlyTheRegion() {
        let old = [0.5, 1.5, 2.5, 3.5].map { DrumHit(time: $0, pad: 0) }
        let new = [DrumHit(time: 2.0, pad: 3)]
        let merged = DrumRenderer.overwrite(old, from: 1.0, to: 3.0, with: new)
        XCTAssertEqual(merged.map(\.time), [0.5, 2.0, 3.5])
        XCTAssertEqual(merged.map(\.pad), [0, 3, 0])
    }

    func testWriteAndEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("track2.caf")
        let frames = try DrumRenderer.write([DrumHit(time: 0.1, pad: 2)], kit: .handPercussion, to: url)
        XCTAssertEqual(try CAFReader(url: url).frameCount, Int64(frames))
        XCTAssertEqual(DrumRenderer.render([], kit: .studio), [])
    }

    func testTrackDrumFieldsRoundTrip() throws {
        var t = Track(index: 1)
        XCTAssertEqual(t.kind, .audio)
        t.kind = .drums
        t.drumKit = .eightOhEight
        t.drumHits = [DrumHit(time: 1.25, pad: 4, velocity: 0.7)]
        let back = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t)
        // Old projects decode as audio tracks.
        let old = try JSONDecoder().decode(Track.self, from: Data(#"{"index":0}"#.utf8))
        XCTAssertEqual(old.kind, .audio)
        XCTAssertEqual(old.drumHits, [])
    }

    private func correlation(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        var ab: Float = 0, aa: Float = 0, bb: Float = 0
        for i in 0..<n { ab += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i] }
        return aa > 0 && bb > 0 ? ab / (aa.squareRoot() * bb.squareRoot()) : 0
    }

    /// Hammering the 808 kick must sound like one kick re-struck, not a stack
    /// of sine tails adding up into distortion.
    func testRepeatedKickIsChokedNotStacked() {
        let kit = DrumKit.eightOhEight
        let single = DrumRenderer.render([DrumHit(time: 0, pad: 0, velocity: 1)], kit: kit)
        let singlePeak = single.map(abs).max() ?? 0
        let hits = (0..<12).map { DrumHit(time: Double($0) * 0.09, pad: 0, velocity: 1) }
        let many = DrumRenderer.render(hits, kit: kit)
        let manyPeak = many.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(manyPeak, singlePeak * 1.001, "re-hits must not pile up")
        // The last hit rings out fully; the earlier ones are cut at the next hit.
        XCTAssertEqual(many.count, Int((11 * 0.09 * 48_000).rounded()) + single.count, accuracy: 2)
        // Every kick before the last is silent at the moment the next one starts.
        for k in 1..<12 {
            let start = Int((Double(k) * 0.09 * 48_000).rounded())
            XCTAssertEqual(many[start - 1], 0, accuracy: 0.02, "kick \(k) still ringing when the next starts")
        }
    }

    /// Closed hat chokes the open hat, like a real hi-hat; other drums overlap.
    func testHiHatsChokeEachOtherButDrumsOverlap() {
        let kit = DrumKit.studioTight
        XCTAssertEqual(DrumVoicing.chokeGroup(kit: kit, pad: 2), DrumVoicing.chokeGroup(kit: kit, pad: 3))
        XCTAssertNotEqual(DrumVoicing.chokeGroup(kit: kit, pad: 0), DrumVoicing.chokeGroup(kit: kit, pad: 1))
        let open = DrumRenderer.render([DrumHit(time: 0, pad: 3)], kit: kit)
        let choked = DrumRenderer.render([DrumHit(time: 0, pad: 3), DrumHit(time: 0.1, pad: 2)], kit: kit)
        let closedAlone = DrumRenderer.render([DrumHit(time: 0.1, pad: 2)], kit: kit)
        // After the fade, only the closed hat is left.
        let after = 4_800 + 200
        let tailLength = min(choked.count, closedAlone.count) - after
        if tailLength > 0, open.count > after + tailLength {
            for k in stride(from: after, to: after + tailLength, by: 97) {
                XCTAssertEqual(choked[k], closedAlone[k], accuracy: 1e-6)
            }
        }
        // Fade, not a hard cut: no jump bigger than the samples themselves make.
        XCTAssertEqual(DrumVoicing.chokeGain(frame: 0, chokeFrame: 10, fadeFrames: 384), 1)
        XCTAssertLessThan(DrumVoicing.chokeGain(frame: 10, chokeFrame: 10, fadeFrames: 384), 1)
        XCTAssertEqual(DrumVoicing.chokeGain(frame: 10 + 384, chokeFrame: 10, fadeFrames: 384), 0)
    }
}
