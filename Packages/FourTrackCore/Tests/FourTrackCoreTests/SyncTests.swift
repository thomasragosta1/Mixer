import XCTest
@testable import FourTrackCore

final class SyncTests: XCTestCase {
    private let a = FileFingerprint(size: 100, modified: 1)
    private let b = FileFingerprint(size: 200, modified: 2)

    func testOutgoingUploadsOnlyChangedFilesAndRetiresOldVersions() {
        let synced = ["track1.caf": SyncedFile(fingerprint: a, remoteID: "r1"),
                      "track2.caf": SyncedFile(fingerprint: a, remoteID: "r2"),
                      "track3.caf": SyncedFile(fingerprint: a, remoteID: "r3")]
        let local = ["track1.caf": a, "track2.caf": b, "track4.caf": b]
        let plan = SyncPlanner.outgoing(local: local, synced: synced, uploading: [:])
        XCTAssertEqual(plan.uploads, ["track2.caf", "track4.caf"], "unchanged track1 stays put")
        XCTAssertEqual(plan.retired, ["r2", "r3"], "re-recorded track2 and deleted track3 free their old copies")
    }

    func testOutgoingSkipsFilesAlreadyUploading() {
        let plan = SyncPlanner.outgoing(local: ["track1.caf": b], synced: [:], uploading: ["track1.caf": b])
        XCTAssertEqual(plan.uploads, [])
    }

    func testIncomingDownloadsNewContentAndRemovesDroppedFiles() {
        let synced = ["track1.caf": SyncedFile(fingerprint: a, remoteID: "r1"),
                      "track2.caf": SyncedFile(fingerprint: a, remoteID: "r2")]
        let local = ["track1.caf": a, "track2.caf": a, "track3.caf": b]
        let plan = SyncPlanner.incoming(remote: ["track1.caf": "r1", "track2.caf": "r9"], synced: synced, local: local)
        XCTAssertEqual(plan.downloads, ["track2.caf": "r9"])
        XCTAssertEqual(plan.removals, ["track3.caf"])
    }

    func testIncomingRedownloadsWhenLocalCopyChangedUnderneath() {
        let synced = ["track1.caf": SyncedFile(fingerprint: a, remoteID: "r1")]
        let plan = SyncPlanner.incoming(remote: ["track1.caf": "r1"], synced: synced, local: ["track1.caf": b])
        XCTAssertEqual(plan.downloads, ["track1.caf": "r1"])
    }

    func testManifestRoundTripAndLedgerMerge() {
        let id = UUID()
        var ledger = SyncLedger()
        ledger.projects[id] = ProjectSyncState(metadataHash: 1, files: ["track1.caf": SyncedFile(fingerprint: a, remoteID: "r1")])
        let up = OutgoingFile(projectID: id, fileName: "track2.caf", fingerprint: b, remoteID: "r2")
        ledger.outgoing[up.recordName] = up
        let manifest = ledger.manifest(for: id)
        XCTAssertEqual(manifest, ["track1.caf": "r1", "track2.caf": "r2"])
        XCTAssertEqual(SyncNames.decodeManifest(SyncNames.encodeManifest(manifest)), manifest)
        XCTAssertEqual(SyncNames.project(ofAudioRecord: up.recordName), id)
        XCTAssertEqual(SyncNames.remoteID(ofAudioRecord: up.recordName), "r2")

        ledger.confirmUpload(recordName: up.recordName)
        XCTAssertTrue(ledger.outgoing.isEmpty)
        XCTAssertEqual(ledger.projects[id]?.files["track2.caf"], SyncedFile(fingerprint: b, remoteID: "r2"))

        let data = try! JSONEncoder().encode(ledger)
        XCTAssertEqual(try! JSONDecoder().decode(SyncLedger.self, from: data), ledger)
        ledger.forget(id)
        XCTAssertNil(ledger.projects[id])
    }

    func testOnlyTrackAudioIsSyncable() {
        XCTAssertTrue(SyncNames.isSyncable("track1.caf"))
        XCTAssertTrue(SyncNames.isSyncable("track1.cleaned.caf"))
        XCTAssertTrue(SyncNames.isSyncable("deleted-1234.caf"))
        XCTAssertFalse(SyncNames.isSyncable(".recording.caf"))
        XCTAssertFalse(SyncNames.isSyncable("track1.caf.splice-1"))
        XCTAssertFalse(SyncNames.isSyncable("track1.peaks"))
        XCTAssertFalse(SyncNames.isSyncable("../evil.caf"))
        XCTAssertEqual(SyncNames.decodeManifest(["../x.caf\u{1F}r", "ok.caf\u{1F}r2", "bad"]), ["ok.caf": "r2"])
    }

    func testStoreReportsChangesAndListsSyncableFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ProjectStore(rootURL: root)
        final class Box: @unchecked Sendable { var ids: [UUID] = [] }
        let box = Box()
        store.onChange = { box.ids.append($0) }
        let p = try store.create(name: "Song")
        try Data([1, 2, 3]).write(to: store.audioURL(project: p.id, track: 0))
        try Data([1]).write(to: store.recordingTempURL(project: p.id))
        try Data([1]).write(to: store.peaksURL(project: p.id, track: 0))
        XCTAssertEqual(Set(store.syncableFiles(in: p.id).keys), ["track1.caf"])
        XCTAssertEqual(store.syncableFiles(in: p.id)["track1.caf"]?.size, 3)
        XCTAssertEqual(store.allProjectIDs(), [p.id])

        let data = try XCTUnwrap(store.metadataData(for: p.id))
        try store.replaceMetadata(data, for: p.id)
        XCTAssertThrowsError(try store.replaceMetadata(data, for: UUID()), "another project's JSON is refused")
        try store.delete(id: p.id)
        XCTAssertEqual(box.ids, [p.id, p.id], "create and delete reported; replaceMetadata isn't")
    }
}
