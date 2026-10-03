import XCTest
@testable import FourTrackCore

final class SplicerTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = try makeTempDir()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    // MARK: CAF round trip

    func testCAFRoundTrip() throws {
        let samples: [Float] = (0..<10_000).map { Float($0 % 200) / 200 - 0.5 }
        try writeCAF(samples, to: url("a.caf"))
        let reader = try CAFReader(url: url("a.caf"))
        XCTAssertEqual(reader.frameCount, 10_000)
        XCTAssertEqual(reader.sampleRate, 48_000)
        XCTAssertEqual(reader.channelCount, 1)
        XCTAssertEqual(try reader.readAll(), samples)
    }

    func testCAFReadOutsideFileIsSilence() throws {
        try writeCAF([1, 2, 3], to: url("a.caf"))
        let r = try CAFReader(url: url("a.caf"))
        XCTAssertEqual(try r.read(from: -2, count: 7), [0, 0, 1, 2, 3, 0, 0])
        XCTAssertEqual(try r.read(from: 10, count: 2), [0, 0])
    }

    func testUnfinishedCAFIsStillReadable() throws {
        // Simulates a crash mid-recording: header still says "size unknown".
        let w = try CAFWriter(url: url("rec.caf"))
        try w.write([0.1, 0.2, 0.3, 0.4])
        let r = try CAFReader(url: url("rec.caf"))
        XCTAssertEqual(try r.readAll(), [0.1, 0.2, 0.3, 0.4])
        try w.finish()
    }

    func testCAFHeaderLayout() throws {
        try writeCAF([0.5], to: url("h.caf"))
        let data = try Data(contentsOf: url("h.caf"))
        XCTAssertEqual(data.count, Int(CAFFormat.headerSize) + 4)
        XCTAssertEqual(data.fourCC(at: 0), "caff")
        XCTAssertEqual(data.fourCC(at: 8), "desc")
        XCTAssertEqual(data.readBE(UInt64.self, at: 12), 32)
        XCTAssertEqual(data.fourCC(at: 52), "data")
        XCTAssertEqual(data.readBE(UInt64.self, at: 56), 8) // edit count + one sample
    }

    func testReaderRejectsNonCAF() throws {
        try Data("RIFF....WAVE".utf8).write(to: url("x.caf"))
        XCTAssertThrowsError(try CAFReader(url: url("x.caf"))) { error in
            XCTAssertEqual(error as? CAFError, .notCAF)
        }
    }

    // MARK: Splice

    func testRecordingOntoEmptyTrack() throws {
        let rec: [Float] = Array(repeating: 0.5, count: 1_000)
        try writeCAF(rec, to: url("rec.caf"))
        let result = try Splicer.splice(.init(trackURL: nil, destinationURL: url("track1.caf"), recordingURL: url("rec.caf"), insertFrame: 0, crossfadeFrames: 0))
        XCTAssertEqual(result.frameCount, 1_000)
        XCTAssertEqual(try readCAF(url("track1.caf")), rec)
    }

    func testRecordingAfterEndPadsWithSilence() throws {
        try writeCAF([1, 1, 1], to: url("rec.caf"))
        try Splicer.splice(.init(trackURL: nil, destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 4, crossfadeFrames: 0))
        XCTAssertEqual(try readCAF(url("t.caf")), [0, 0, 0, 0, 1, 1, 1])
    }

    func testOverwriteMiddlePreservesBeforeAndAfter() throws {
        let old: [Float] = (0..<100).map { Float($0) }
        try writeCAF(old, to: url("t.caf"))
        try writeCAF(Array(repeating: -1, count: 20), to: url("rec.caf"))
        let r = try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 40, crossfadeFrames: 0))
        XCTAssertEqual(r.frameCount, 100)
        XCTAssertEqual(r.replacedStart, 40)
        XCTAssertEqual(r.replacedEnd, 60)
        let out = try readCAF(url("t.caf"))
        XCTAssertEqual(Array(out[0..<40]), Array(old[0..<40]))
        XCTAssertEqual(Array(out[40..<60]), Array(repeating: -1, count: 20))
        XCTAssertEqual(Array(out[60..<100]), Array(old[60..<100]))
    }

    func testRecordingPastEndGrowsTrack() throws {
        try writeCAF(Array(repeating: 0.25, count: 50), to: url("t.caf"))
        try writeCAF(Array(repeating: 0.75, count: 30), to: url("rec.caf"))
        let r = try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 40, crossfadeFrames: 0))
        XCTAssertEqual(r.frameCount, 70)
        let out = try readCAF(url("t.caf"))
        XCTAssertEqual(Array(out[0..<40]), Array(repeating: 0.25, count: 40))
        XCTAssertEqual(Array(out[40..<70]), Array(repeating: 0.75, count: 30))
    }

    func testSkipAndLimitApplyLatencyCompensation() throws {
        // Recording has 10 frames of pre-roll/latency, then the real take.
        let rec: [Float] = Array(repeating: 9, count: 10) + [1, 2, 3, 4, 5]
        try writeCAF(rec, to: url("rec.caf"))
        try writeCAF(Array(repeating: 0, count: 8), to: url("t.caf"))
        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), recordingSkipFrames: 10, recordingFrameLimit: 3, insertFrame: 2, crossfadeFrames: 0))
        XCTAssertEqual(try readCAF(url("t.caf")), [0, 0, 1, 2, 3, 0, 0, 0])
    }

    func testNegativeInsertDropsAudioBeforeZero() throws {
        try writeCAF([1, 2, 3, 4], to: url("rec.caf"))
        try Splicer.splice(.init(trackURL: nil, destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: -2, crossfadeFrames: 0))
        XCTAssertEqual(try readCAF(url("t.caf")), [3, 4])
    }

    func testInputGainIsAppliedOnlyToNewAudio() throws {
        try writeCAF([0.5, 0.5, 0.5, 0.5], to: url("t.caf"))
        try writeCAF([0.25, 0.25], to: url("rec.caf"))
        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 1, crossfadeFrames: 0, inputGainDB: 20 * log10(2)))
        let out = try readCAF(url("t.caf"))
        XCTAssertEqual(out[0], 0.5)
        XCTAssertEqual(out[1], 0.5, accuracy: 1e-5)
        XCTAssertEqual(out[2], 0.5, accuracy: 1e-5)
        XCTAssertEqual(out[3], 0.5)
    }

    func testEmptyRecordingLeavesTrackUnchanged() throws {
        let old: [Float] = [1, 2, 3]
        try writeCAF(old, to: url("t.caf"))
        try writeCAF([], to: url("rec.caf"))
        let r = try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 10))
        XCTAssertEqual(r.frameCount, 3)
        XCTAssertEqual(try readCAF(url("t.caf")), old)
    }

    func testCrossfadesRemoveClicks() throws {
        // Old take: a 220 Hz sine. New take: an out-of-phase 330 Hz sine.
        // Without crossfades the edges jump; with 5 ms equal-power fades
        // no step may exceed what the signals themselves produce.
        let old = sine(frequency: 220, seconds: 1, amplitude: 0.8)
        var new = sine(frequency: 330, seconds: 0.3, amplitude: 0.8)
        new = new.map { -$0 }
        try writeCAF(old, to: url("t.caf"))
        try writeCAF(new, to: url("rec.caf"))

        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("hard.caf"), recordingURL: url("rec.caf"), insertFrame: 12_345, crossfadeFrames: 0))
        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("soft.caf"), recordingURL: url("rec.caf"), insertFrame: 12_345))

        let hard = try readCAF(url("hard.caf"))
        let soft = try readCAF(url("soft.caf"))
        // Natural max step of the source signals.
        let natural = max(maxStep(old[...]), maxStep(new[...]))
        let start = 12_345, end = 12_345 + new.count
        let hardStep = max(maxStep(hard[(start - 2)...(start + 2)]), maxStep(hard[(end - 2)...(end + 2)]))
        let softStep = max(maxStep(soft[(start - 300)...(start + 300)]), maxStep(soft[(end - 300)...(end + 300)]))
        XCTAssertGreaterThan(hardStep, natural * 2, "test signal should click without fades")
        XCTAssertLessThanOrEqual(softStep, natural * 1.5)
        // Outside the fades the new audio is untouched.
        XCTAssertEqual(soft[start + 1_000], new[1_000], accuracy: 1e-6)
        XCTAssertEqual(soft[start - 1], old[start - 1])
        XCTAssertEqual(soft[end], old[end])
    }

    func testCrossfadeShrinksForShortRecordings() throws {
        try writeCAF(Array(repeating: 0, count: 100), to: url("t.caf"))
        try writeCAF(Array(repeating: 1, count: 10), to: url("rec.caf"))
        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 50, crossfadeFrames: 240))
        let out = try readCAF(url("t.caf"))
        // Fade covers half the take each side; the middle reaches near full level.
        XCTAssertGreaterThan(out[54], 0.9)
        XCTAssertGreaterThan(out[55], 0.9)
        XCTAssertLessThan(out[50], 0.2)
        XCTAssertLessThan(out[59], 0.2)
        XCTAssertEqual(out[49], 0)
        XCTAssertEqual(out[60], 0)
    }

    func testEqualPowerWeights() {
        for p in 0..<240 {
            let w = Splicer.weights(position: Int64(p), length: 10_000, fade: 240)
            XCTAssertEqual(w.old * w.old + w.new * w.new, 1, accuracy: 1e-5)
        }
        XCTAssertEqual(Splicer.weights(position: 5_000, length: 10_000, fade: 240).new, 1)
    }

    func testSpliceAcrossChunkBoundaries() throws {
        let n = Splicer.chunkFrames * 2 + 1_234
        let old: [Float] = (0..<n).map { Float($0 % 1_000) / 1_000 }
        try writeCAF(old, to: url("t.caf"))
        let recLen = Splicer.chunkFrames + 77
        let rec: [Float] = (0..<recLen).map { -Float($0 % 500) / 500 }
        try writeCAF(rec, to: url("rec.caf"))
        let insert = Splicer.chunkFrames - 100
        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: Int64(insert), crossfadeFrames: 0))
        let out = try readCAF(url("t.caf"))
        XCTAssertEqual(out.count, n)
        XCTAssertEqual(Array(out[0..<insert]), Array(old[0..<insert]))
        XCTAssertEqual(Array(out[insert..<(insert + recLen)]), rec)
        XCTAssertEqual(Array(out[(insert + recLen)...]), Array(old[(insert + recLen)...]))
    }

    // MARK: Atomicity

    func testFailedSpliceLeavesOriginalAndNoTempFiles() throws {
        let old: [Float] = [1, 2, 3]
        try writeCAF(old, to: url("t.caf"))
        // Recording file is not a CAF: splice must throw before touching the take.
        try Data("garbage".utf8).write(to: url("rec.caf"))
        XCTAssertThrowsError(try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 0)))
        XCTAssertEqual(try readCAF(url("t.caf")), old)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("splice") }
        XCTAssertEqual(leftovers, [])
    }

    func testSpliceWritesThroughTempAndRename() throws {
        try writeCAF([1, 2, 3], to: url("t.caf"))
        try writeCAF([9], to: url("rec.caf"))
        // Hold the old file open across the splice: the reader keeps seeing the
        // old take (rename replaces the directory entry, not the data).
        let before = try CAFReader(url: url("t.caf"))
        try Splicer.splice(.init(trackURL: url("t.caf"), destinationURL: url("t.caf"), recordingURL: url("rec.caf"), insertFrame: 1, crossfadeFrames: 0))
        XCTAssertEqual(try before.readAll(), [1, 2, 3])
        XCTAssertEqual(try readCAF(url("t.caf")), [1, 9, 3])
    }
}
