import XCTest
@testable import Fauna

/// Publishing new animals, and keeping enough unmet animals ready for offline reading.
@MainActor
final class LibraryUpdateTests: XCTestCase {
    private func onboarded(_ library: [Animal]) -> AppStore {
        let store = AppStore(library: library, fileURL: nil)
        store.completeOnboarding()
        return store
    }

    private func renamed(_ a: Animal, _ id: String) throws -> Animal {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        json["id"] = id
        json["name"] = a.name + " " + id
        json["wikipediaTitle"] = a.wikipediaTitle + " " + id
        return try JSONDecoder().decode(Animal.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testNewlyPublishedAnimalsJoinTheQueue() throws {
        let all = AnimalLibrary.load()
        let store = onboarded(Array(all.prefix(40)))
        let today = store.currentAnimal?.id
        let added = try (0..<5).map { try renamed(all[$0], "new\($0)") }
        store.applyLibrary(Array(all.prefix(40)) + added)
        XCTAssertEqual(store.library.count, 45)
        for a in added { XCTAssertTrue(store.state.queue.contains(a.id), a.id) }
        XCTAssertEqual(store.currentAnimal?.id, today, "today's animal doesn't change")
    }

    func testRemovedAnimalsLeaveTheQueueButNotTheJournal() {
        let all = AnimalLibrary.load()
        let store = onboarded(all)
        let today = store.currentAnimal!.id
        let trimmed = all.filter { $0.id != today && !store.state.queue.prefix(3).contains($0.id) }
        let removedFromQueue = Array(store.state.queue.prefix(3))
        store.applyLibrary(trimmed)
        for id in removedFromQueue { XCTAssertFalse(store.state.queue.contains(id)) }
        XCTAssertTrue(store.state.journal.contains { $0.animalID == today }, "journal history is kept")
        XCTAssertNotNil(store.currentAnimal, "a removed daily animal is replaced")
    }

    func testPublishingTheSameLibraryChangesNothing() {
        let all = AnimalLibrary.load()
        let store = onboarded(all)
        let before = store.state
        store.applyLibrary(all)
        XCTAssertEqual(store.state, before)
    }

    func testAtLeastThirtyUnmetAnimalsAreLinedUpForOffline() {
        let store = onboarded(AnimalLibrary.load())
        let upcoming = store.upcomingForOffline(count: OfflineLibrary.target)
        XCTAssertGreaterThanOrEqual(OfflineLibrary.target, 30)
        XCTAssertEqual(upcoming.count, OfflineLibrary.target)
        XCTAssertEqual(upcoming.first?.id, store.currentAnimal?.id, "today's animal comes first")
        XCTAssertEqual(Set(upcoming.map(\.id)).count, upcoming.count)
        XCTAssertGreaterThanOrEqual(upcoming.dropFirst().filter { !store.metIDs.contains($0.id) }.count, 30)
        XCTAssertEqual(Array(upcoming.dropFirst().prefix(5).map(\.id)), Array(store.state.queue.prefix(5)),
                       "then the animals the daily queue will bring")
    }

    func testOfflineListFollowsUnlocks() {
        let store = onboarded(AnimalLibrary.load())
        let next = store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true)!
        let upcoming = store.upcomingForOffline(count: 10)
        XCTAssertEqual(upcoming.first?.id, next.id)
        XCTAssertFalse(upcoming.dropFirst().contains { store.metIDs.contains($0.id) })
    }

    func testOnlyCompleteLibrariesAreAccepted() throws {
        let all = AnimalLibrary.load()
        let good = try JSONEncoder().encode(all)
        XCTAssertEqual(ContentSync.decodeLibrary(good)?.count, all.count)
        XCTAssertNil(ContentSync.decodeLibrary(Data("<html>404</html>".utf8)), "an error page is ignored")
        XCTAssertNil(ContentSync.decodeLibrary(good.prefix(good.count / 2)), "a half-downloaded file is ignored")
        XCTAssertNil(ContentSync.decodeLibrary(try JSONEncoder().encode(Array(all.prefix(3)))), "a near-empty library is ignored")
        XCTAssertNil(ContentSync.decodeLibrary(try JSONEncoder().encode(all + [all[0]])), "duplicate ids are rejected")
    }

    func testBundleHashIsStable() {
        XCTAssertEqual(ContentSync.bundleHash().count, 64)
        XCTAssertEqual(ContentSync.bundleHash(), ContentSync.bundleHash())
    }

    func testPublishedFilesPointAtThisRepository() {
        XCTAssertEqual(ContentSync.baseURL.host(), "raw.githubusercontent.com")
        XCTAssertTrue(ContentSync.baseURL.absoluteString.hasSuffix("/Fauna/Fauna/Resources/"))
    }
}
