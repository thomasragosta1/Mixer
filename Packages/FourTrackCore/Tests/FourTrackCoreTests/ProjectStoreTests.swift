import XCTest
@testable import FourTrackCore

final class ProjectStoreTests: XCTestCase {
    var dir: URL!
    var store: ProjectStore!

    override func setUpWithError() throws {
        dir = try makeTempDir()
        store = try ProjectStore(rootURL: dir.appendingPathComponent("Projects"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testNewProjectHasFourDefaultTracks() throws {
        let p = try store.create()
        XCTAssertEqual(p.tracks.count, 4)
        XCTAssertEqual(p.tracks.map(\.name), ["Track 1", "Track 2", "Track 3", "Track 4"])
        XCTAssertEqual(p.tracks.map(\.index), [0, 1, 2, 3])
        XCTAssertTrue(p.tracks.allSatisfy { $0.isEmpty && $0.volume == 0.75 && $0.cleanup == 0 && $0.compressor == 0.3 })
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL(for: p.id).path))
    }

    func testSaveAndLoadRoundTrip() throws {
        var p = try store.create(name: "Song", now: Date(timeIntervalSince1970: 1_700_000_000))
        p.tracks[2].name = "Vocal"
        p.tracks[2].eqHigh = 0.4
        p.tracks[1].mute = true
        p.tracks[3].devOverrides = DevParams(compressor: MacroCurves.compressor(0.9), inputGainDB: 6)
        p.playheadSeconds = 12.5
        p.metronome.bpm = 92
        try store.save(p)
        let loaded = try store.load(id: p.id)
        XCTAssertEqual(loaded, p)
    }

    func testListIsNewestFirstAndSkipsJunk() throws {
        let a = try store.create(name: "A", now: Date(timeIntervalSince1970: 1_000))
        let b = try store.create(name: "B", now: Date(timeIntervalSince1970: 2_000))
        try FileManager.default.createDirectory(at: store.rootURL.appendingPathComponent("not-a-project"), withIntermediateDirectories: true)
        let broken = UUID()
        try FileManager.default.createDirectory(at: store.directory(for: broken), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: store.metadataURL(for: broken))
        XCTAssertEqual(store.loadAll().map(\.id), [b.id, a.id])
        // Unreadable projects are skipped, never deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL(for: broken).path))
    }

    func testDeleteRemovesFolder() throws {
        let p = try store.create()
        try writeCAF([1], to: store.audioURL(project: p.id, track: 0))
        try store.delete(id: p.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: p.id).path))
        XCTAssertEqual(store.loadAll(), [])
    }

    func testDefaultNamesIncrement() throws {
        XCTAssertEqual(try store.create().name, "New Project")
        XCTAssertEqual(try store.create().name, "New Project 2")
        XCTAssertEqual(try store.create().name, "New Project 3")
    }

    func testDecodingAlwaysYieldsFourTracks() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Old","createdAt":1735689600,
         "tracks":[{"index":2,"name":"Only"},{"index":7,"name":"Bogus"}]}
        """
        try FileManager.default.createDirectory(at: store.directory(for: id), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.metadataURL(for: id))
        let p = try store.load(id: id)
        XCTAssertEqual(p.tracks.count, 4)
        XCTAssertEqual(p.tracks[2].name, "Only")
        XCTAssertEqual(p.tracks[0].name, "Track 1")
        XCTAssertEqual(p.tracks[2].volume, 0.75)
        XCTAssertEqual(p.masterVolume, 0.75)
    }

    func testRefreshDurationsUsesLongestTrack() throws {
        var p = try store.create()
        try writeCAF(Array(repeating: 0, count: 48_000), to: store.audioURL(project: p.id, track: 0))
        try writeCAF(Array(repeating: 0, count: 96_000), to: store.audioURL(project: p.id, track: 3))
        p.tracks[0].audioFileName = ProjectStore.audioFileName(track: 0)
        p.tracks[3].audioFileName = ProjectStore.audioFileName(track: 3)
        store.refreshDurations(&p)
        XCTAssertEqual(p.tracks[0].durationSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(p.tracks[3].durationSeconds, 2, accuracy: 1e-9)
        XCTAssertEqual(p.durationSeconds, 2, accuracy: 1e-9)
    }

    func testPendingRecordingRecovery() throws {
        let p = try store.create()
        XCTAssertNil(store.pendingRecording(project: p.id))
        let pending = PendingRecording(trackIndex: 1, insertFrame: 4_800, skipFrames: 0, inputGainDB: 0, route: .wired)
        try store.savePendingRecording(pending, project: p.id)
        // Marker alone (no audio captured) is not recoverable.
        XCTAssertNil(store.pendingRecording(project: p.id))
        try writeCAF([0.1, 0.2], to: store.recordingTempURL(project: p.id))
        XCTAssertEqual(store.pendingRecording(project: p.id), pending)
        store.clearPendingRecording(project: p.id)
        XCTAssertNil(store.pendingRecording(project: p.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.recordingTempURL(project: p.id).path))
    }

    func testCleanTemporaryFiles() throws {
        let p = try store.create()
        let junk = store.directory(for: p.id).appendingPathComponent(".track1.caf.splice-123")
        try Data([1]).write(to: junk)
        store.cleanTemporaryFiles(project: p.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: junk.path))
    }

    func testBinKeepsProjectsUntilPermanentDelete() throws {
        let a = try store.create(name: "A", now: Date(timeIntervalSince1970: 1_000))
        let b = try store.create(name: "B", now: Date(timeIntervalSince1970: 2_000))
        try writeCAF([1], to: store.audioURL(project: a.id, track: 0))

        try store.moveToBin(id: a.id, now: Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(store.loadAll().map(\.id), [b.id])
        XCTAssertEqual(store.loadBin().map(\.id), [a.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioURL(project: a.id, track: 0).path))

        try store.restore(id: a.id)
        XCTAssertEqual(store.loadAll().map(\.id), [b.id, a.id])
        XCTAssertEqual(store.loadBin(), [])

        try store.moveToBin(id: a.id)
        try store.delete(id: a.id)
        XCTAssertEqual(store.loadBin(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: a.id).path))
    }

    func testVisibleTrackCount() throws {
        var p = try store.create()
        XCTAssertEqual(p.visibleTrackCount, 1)
        p.visibleTrackCount = 3
        try store.save(p)
        XCTAssertEqual(try store.load(id: p.id).visibleTrackCount, 3)

        // Older projects without the field show every lane that has audio.
        var old = Project(name: "Old")
        old.tracks[2].audioFileName = "track3.caf"
        old.visibleTrackCount = 1
        old.normalizeTracks()
        XCTAssertEqual(old.visibleTrackCount, 3)
        old.visibleTrackCount = 9
        old.normalizeTracks()
        XCTAssertEqual(old.visibleTrackCount, 4)
    }

    func testSoloAndMuteAudibility() {
        var p = Project(name: "x")
        XCTAssertTrue((0..<4).allSatisfy { p.isAudible($0) })
        p.tracks[1].mute = true
        XCTAssertFalse(p.isAudible(1))
        p.tracks[2].solo = true
        XCTAssertEqual((0..<4).map { p.isAudible($0) }, [false, false, true, false])
        p.tracks[1].solo = true // muted beats solo
        XCTAssertEqual((0..<4).map { p.isAudible($0) }, [false, false, true, false])
    }

    func testLatencySettings() throws {
        var s = LatencySettings()
        XCTAssertEqual(s.compensation(for: .wired, estimate: 0.012), 0.012, accuracy: 1e-12)
        s.measured[.wired] = 0.010
        s.manualOffsetMs[.wired] = 2
        XCTAssertEqual(s.compensation(for: .wired, estimate: 0.5), 0.012, accuracy: 1e-12)
        s.manualOffsetMs[.speaker] = -100
        XCTAssertEqual(s.compensation(for: .speaker, estimate: 0.02), 0)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(LatencySettings.self, from: data), s)
        XCTAssertEqual(LatencyModel.estimate(inputLatency: 0.002, outputLatency: 0.003, ioBufferDuration: 0.005), 0.015, accuracy: 1e-12)
    }
}
