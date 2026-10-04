import XCTest
@testable import FourTrackCore

final class TrackBinTests: XCTestCase {
    private var dir: URL!
    private var store: ProjectStore!

    override func setUpWithError() throws {
        dir = try makeTempDir()
        store = try ProjectStore(rootURL: dir.appendingPathComponent("Projects"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func record(_ project: inout Project, track: Int, seconds: Double = 1) throws {
        let url = store.audioURL(project: project.id, track: track)
        let w = try CAFWriter(url: url)
        try w.write([Float](repeating: 0.1, count: Int(48_000 * seconds)))
        try w.finish()
        project.tracks[track].audioFileName = ProjectStore.audioFileName(track: track)
    }

    func testDeleteMovesTrackToProjectBinAndHidesLane() throws {
        var p = try store.create()
        p.visibleTrackCount = 3
        try record(&p, track: 0, seconds: 2)
        try record(&p, track: 1, seconds: 1)
        p.tracks[1].name = "Vocal"
        p.tracks[1].volume = 0.5
        try store.binTrack(&p, index: 1)

        XCTAssertEqual(p.visibleLanes, [0, 2])
        XCTAssertTrue(p.tracks[1].isEmpty)
        XCTAssertEqual(p.tracks[1].name, "Track 2")
        XCTAssertEqual(p.deletedTracks.count, 1)
        let binned = p.deletedTracks[0]
        XCTAssertEqual(binned.track.name, "Vocal")
        XCTAssertEqual(binned.track.volume, 0.5)
        let audio = store.fileURL(binned.track.audioFileName!, in: p.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.audioURL(project: p.id, track: 1).path))

        // Round-trips through JSON.
        try store.save(p)
        XCTAssertEqual(try store.load(id: p.id).deletedTracks.map(\.track), p.deletedTracks.map(\.track))
    }

    func testRecoverPutsTrackBackWithItsAudio() throws {
        var p = try store.create()
        p.visibleTrackCount = 2
        try record(&p, track: 0)
        try record(&p, track: 1)
        p.tracks[1].name = "Guitar"
        try store.binTrack(&p, index: 1)
        let id = p.deletedTracks[0].id
        let slot = try store.recoverTrack(&p, id: id)

        XCTAssertTrue(p.visibleLanes.contains(slot))
        XCTAssertEqual(p.tracks[slot].name, "Guitar")
        XCTAssertEqual(p.tracks[slot].index, slot)
        XCTAssertEqual(p.tracks[slot].audioFileName, ProjectStore.audioFileName(track: slot))
        XCTAssertEqual(try CAFReader(url: store.audioURL(project: p.id, track: slot)).frameCount, 48_000)
        XCTAssertTrue(p.deletedTracks.isEmpty)
    }

    func testRecoverIntoEmptyVisibleLaneFirst() throws {
        var p = try store.create()
        try record(&p, track: 0)
        try store.binTrack(&p, index: 0)
        // The only lane stays on screen, now empty.
        XCTAssertEqual(p.visibleLanes, [0])
        XCTAssertTrue(p.tracks[0].isEmpty)
        XCTAssertEqual(try store.recoverTrack(&p, id: p.deletedTracks[0].id), 0)
        XCTAssertEqual(p.visibleLanes, [0])
        XCTAssertFalse(p.tracks[0].isEmpty)
    }

    func testRecoverFailsWhenAllLanesFull() throws {
        var p = try store.create()
        p.visibleTrackCount = 4
        for i in 0..<4 { try record(&p, track: i) }
        try store.binTrack(&p, index: 2)
        try record(&p, track: 2)
        p.visibleTrackCount = 4
        p.normalizeTracks()
        XCTAssertThrowsError(try store.recoverTrack(&p, id: p.deletedTracks[0].id)) {
            XCTAssertEqual($0 as? ProjectStore.TrackBinError, .noFreeLane)
        }
    }

    func testPermanentDeleteRemovesAudio() throws {
        var p = try store.create()
        try record(&p, track: 0)
        try store.binTrack(&p, index: 0)
        let url = store.fileURL(p.deletedTracks[0].track.audioFileName!, in: p.id)
        store.deleteTrackPermanently(&p, id: p.deletedTracks[0].id)
        XCTAssertTrue(p.deletedTracks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
