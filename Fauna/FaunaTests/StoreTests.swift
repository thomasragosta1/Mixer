import XCTest
@testable import Fauna

/// The daily flow, unlocking, focus, persistence and streaks.
@MainActor
final class StoreTests: XCTestCase {
    private let cal = Calendar.current

    private func onboarded(groups: Set<AnimalGroup> = [], regions: Set<Region> = [], fileURL: URL? = nil) -> AppStore {
        let store = AppStore(fileURL: fileURL)
        store.setFocus(groups: groups, regions: regions)
        store.completeOnboarding()
        return store
    }

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: .now)! }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fauna-test-\(UUID().uuidString).json")
    }

    /// The saved form of a state. Dates are stored to the second, so compare what's on disk.
    private func saved(_ state: AppState) -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return try! e.encode(state)
    }

    /// Invariants that must hold after any sequence of actions.
    private func assertConsistent(_ store: AppStore, file: StaticString = #filePath, line: UInt = #line) {
        let s = store.state
        XCTAssertEqual(Set(s.journal.map(\.animalID)).count, s.journal.count, "journal has duplicates", file: file, line: line)
        XCTAssertTrue(Set(s.todayChain).isSubset(of: store.metIDs), "today's animals missing from journal", file: file, line: line)
        XCTAssertEqual(Set(s.todayChain).count, s.todayChain.count, "an animal appears twice today", file: file, line: line)
        XCTAssertTrue(Set(s.queue).isDisjoint(with: store.metIDs), "queue holds a met animal", file: file, line: line)
        XCTAssertEqual(Set(s.quizPassedIDs).count, s.quizPassedIDs.count, "duplicate quiz passes", file: file, line: line)
    }

    // MARK: Daily flow

    func testNothingHappensBeforeOnboarding() {
        let store = AppStore(fileURL: nil)
        store.refreshDay()
        XCTAssertNil(store.currentAnimal)
        XCTAssertTrue(store.state.journal.isEmpty)
    }

    func testOnboardingAssignsTodaysAnimal() {
        let store = onboarded()
        XCTAssertNotNil(store.currentAnimal)
        XCTAssertEqual(store.state.journal.count, 1)
        XCTAssertEqual(store.state.journal.first?.source, .daily)
        XCTAssertEqual(store.dayNumber, 1)
        assertConsistent(store)
    }

    func testRefreshingTheSameDayKeepsTheAnimal() {
        let store = onboarded()
        let first = store.currentAnimal?.id
        for _ in 0..<20 { store.refreshDay() }
        XCTAssertEqual(store.currentAnimal?.id, first)
        XCTAssertEqual(store.state.journal.count, 1)
    }

    func testNewDayBringsANewAnimal() {
        let store = onboarded()
        let first = store.currentAnimal?.id
        store.refreshDay(now: day(1))
        XCTAssertNotEqual(store.currentAnimal?.id, first)
        XCTAssertEqual(store.state.todayChain.count, 1)
        XCTAssertEqual(store.state.journal.count, 2)
        assertConsistent(store)
    }

    func testEveryAnimalAppearsOnceBeforeAnyRepeat() {
        let store = onboarded()
        var seen = [store.currentAnimal!.id]
        for d in 1..<store.library.count {
            store.refreshDay(now: day(d))
            seen.append(store.currentAnimal!.id)
        }
        XCTAssertEqual(Set(seen).count, store.library.count)
        XCTAssertTrue(store.undiscovered.isEmpty)
        // With everything met, the next day revisits the animal seen longest ago.
        store.refreshDay(now: day(store.library.count))
        XCTAssertEqual(store.currentAnimal?.id, seen.first)
        assertConsistent(store)
    }

    func testUnknownTodayAnimalIsReplaced() {
        let store = onboarded()
        var s = store.state
        s.todayChain = ["an-animal-removed-in-an-update"]
        store.state = s
        XCTAssertNil(store.currentAnimal)
        store.refreshDay()
        XCTAssertNotNil(store.currentAnimal, "Today must not stay empty until midnight")
    }

    // MARK: Unlocking

    func testPassingAQuizUnlocksAnotherAnimal() {
        let store = onboarded()
        let today = store.currentAnimal!
        let next = store.unlockNext(for: today, allowOutsideFocus: true)
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next?.id, today.id)
        XCTAssertEqual(store.currentAnimal?.id, next?.id)
        XCTAssertTrue(store.hasPassedQuiz(today))
        XCTAssertEqual(store.state.journal.last?.source, .unlocked)
        assertConsistent(store)
    }

    func testUnlimitedUnlocksUntilEverythingIsMet() {
        let store = onboarded()
        var unlocked = 0
        while let current = store.currentAnimal, let _ = store.unlockNext(for: current, allowOutsideFocus: true) {
            unlocked += 1
            if unlocked >= 200 { return XCTFail("unlocking never ends") }
        }
        XCTAssertEqual(unlocked, store.library.count - 1)
        XCTAssertFalse(store.canUnlockAnywhere)
        XCTAssertNil(store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true))
        XCTAssertEqual(store.state.todayChain.count, store.library.count)
        assertConsistent(store)
    }

    func testUnlockingStaysInsideFocus() {
        let store = onboarded(groups: [.insect], regions: [.naEast])
        let pool = Set(store.focusPool.map(\.id))
        XCTAssertFalse(pool.isEmpty)
        var current = store.currentAnimal!
        while let next = store.unlockNext(for: current, allowOutsideFocus: false) {
            XCTAssertTrue(pool.contains(next.id), "\(next.id) is outside the focus")
            current = next
        }
        XCTAssertFalse(store.canUnlockInFocus)
        // Once the focus is exhausted, the reader can still choose an animal from anywhere.
        XCTAssertNotNil(store.unlockNext(for: current, allowOutsideFocus: true))
        assertConsistent(store)
    }

    func testMarkQuizPassedIsIdempotent() {
        let store = onboarded()
        let a = store.currentAnimal!
        for _ in 0..<5 { store.markQuizPassed(a) }
        XCTAssertEqual(store.state.quizPassedIDs, [a.id])
    }

    // MARK: Focus

    func testEmptyFocusMatchesEverything() {
        let store = AppStore(fileURL: nil)
        XCTAssertEqual(store.focusPool.count, store.library.count)
        XCTAssertFalse(store.hasFocus)
    }

    func testFocusNeedsBothKindAndPlace() {
        let store = AppStore(fileURL: nil)
        store.setFocus(groups: [.insect], regions: [.naEast])
        XCTAssertTrue(store.focusPool.allSatisfy { $0.group == .insect && $0.regions.contains(.naEast) })
        store.setFocus(groups: [.bird, .fish], regions: [])
        XCTAssertTrue(store.focusPool.allSatisfy { [.bird, .fish].contains($0.group) })
    }

    func testFocusQueueOnlyHoldsMatchingUnmetAnimals() {
        let store = onboarded()
        store.setFocus(groups: [.mammal], regions: [])
        XCTAssertFalse(store.state.queue.isEmpty)
        for id in store.state.queue {
            XCTAssertEqual(store.animal(id)?.group, .mammal)
            XCTAssertFalse(store.metIDs.contains(id))
        }
    }

    func testImpossibleFocusStillGivesADailyAnimal() {
        let store = onboarded(groups: [.fish], regions: [.antarctica])
        XCTAssertTrue(store.focusPool.isEmpty)
        XCTAssertNotNil(store.currentAnimal)
        store.refreshDay(now: day(1))
        XCTAssertNotNil(store.currentAnimal)
    }

    func testFocusSummary() {
        let store = AppStore(fileURL: nil)
        XCTAssertEqual(store.focusSummary, "Every animal, everywhere")
        store.setFocus(groups: [.bird], regions: [])
        XCTAssertEqual(store.focusSummary, "Birds")
        store.setFocus(groups: [], regions: [.naEast])
        XCTAssertEqual(store.focusSummary, "Anything in E. North America")
        store.setFocus(groups: [.insect], regions: [.naEast])
        XCTAssertEqual(store.focusSummary, "Insects & Bugs in E. North America")
    }

    // MARK: Persistence

    func testStateSurvivesARelaunch() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = onboarded(groups: [.bird], fileURL: url)
        store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true)
        store.state.units = .imperial
        let relaunched = AppStore(fileURL: url)
        XCTAssertEqual(saved(relaunched.state), saved(store.state))
        XCTAssertEqual(relaunched.currentAnimal?.id, store.currentAnimal?.id)
    }

    func testCorruptSaveFileStartsFresh() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json at all {".utf8).write(to: url)
        let store = AppStore(fileURL: url)
        XCTAssertEqual(store.state, AppState())
    }

    func testOldOrPartialSaveFilesStillLoad() throws {
        let json = #"{"hasOnboarded":true,"queue":["axolotl"],"focusGroups":["dragon"],"units":"furlongs"}"#
        let state = try JSONDecoder.fauna.decode(AppState.self, from: Data(json.utf8))
        XCTAssertTrue(state.hasOnboarded)
        XCTAssertEqual(state.queue, ["axolotl"])
        XCTAssertEqual(state.focusGroups, [], "unknown kinds are dropped, not fatal")
        XCTAssertEqual(state.units, .automatic, "unknown units fall back to automatic")
        XCTAssertEqual(state.reminderHour, 8)
    }

    func testResetKeepsSettingsAndClearsProgress() {
        let store = onboarded(groups: [.mammal])
        store.state.units = .metric
        store.state.reminderHour = 21
        for _ in 0..<5 { store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true) }
        store.resetProgress()
        XCTAssertEqual(store.state.journal.count, 1)
        XCTAssertEqual(store.state.todayChain.count, 1)
        XCTAssertTrue(store.state.quizPassedIDs.isEmpty)
        XCTAssertEqual(store.state.units, .metric)
        XCTAssertEqual(store.state.reminderHour, 21)
        XCTAssertEqual(store.state.focusGroups, [.mammal])
        assertConsistent(store)
    }

    // MARK: Journal, streaks, units

    func testStreakCountsConsecutiveDays() {
        let store = AppStore(fileURL: nil)
        var s = AppState()
        s.journal = [0, -1, -2, -4].enumerated().map { i, offset in
            JournalEntry(animalID: store.library[i].id, date: day(offset), source: .daily)
        }
        store.state = s
        XCTAssertEqual(store.streak, 3, "the gap two days ago ends the streak")
    }

    func testStreakSurvivesUntilTodaysAnimalIsOpened() {
        let store = AppStore(fileURL: nil)
        var s = AppState()
        s.journal = [-1, -2].enumerated().map { i, offset in
            JournalEntry(animalID: store.library[i].id, date: day(offset), source: .daily)
        }
        store.state = s
        XCTAssertEqual(store.streak, 2)
    }

    func testJournalIsNewestFirstAndSkipsRemovedAnimals() {
        let store = AppStore(fileURL: nil)
        var s = AppState()
        s.journal = [
            JournalEntry(animalID: "axolotl", date: day(-3), source: .daily),
            JournalEntry(animalID: "no-longer-exists", date: day(-2), source: .daily),
            JournalEntry(animalID: "okapi", date: day(-1), source: .daily),
        ]
        store.state = s
        XCTAssertEqual(store.journalAnimals.map(\.animal.id), ["okapi", "axolotl"])
    }

    func testDayKeyIsZeroPadded() {
        let date = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 12))!
        XCTAssertEqual(AppStore.dayKey(for: date), "2026-01-05")
    }

    func testMeasuredFollowsTheUnitsSetting() {
        let store = AppStore(fileURL: nil)
        store.state.units = .imperial
        XCTAssertEqual(store.measured("Up to ~30 m"), "Up to ~98 ft")
        store.state.units = .metric
        XCTAssertEqual(store.measured("Up to ~30 m"), "Up to ~30 m")
    }

    func testDemoStore() {
        let store = AppStore.demo()
        XCTAssertEqual(store.currentAnimal?.id, "red-panda")
        XCTAssertEqual(store.metIDs.count, 12)
        XCTAssertEqual(store.streak, 12)
        XCTAssertTrue(store.hasPassedQuiz(store.animal("axolotl")!))
        XCTAssertFalse(store.hasPassedQuiz(store.animal("red-panda")!))
        assertConsistent(store)
    }

    func testUpcomingAnimalsFollowTheQueue() {
        let store = onboarded()
        let upcoming = store.upcomingDailyAnimals(count: 30).map(\.id)
        XCTAssertEqual(upcoming, Array(store.state.queue.prefix(30)))
        store.refreshDay(now: day(1))
        XCTAssertEqual(store.currentAnimal?.id, upcoming.first, "tomorrow's notification names tomorrow's animal")
    }

    // MARK: Stress

    /// Thousands of random actions in random order; the store must stay consistent throughout.
    func testRandomActionsKeepTheStoreConsistent() {
        let store = onboarded()
        var offset = 0
        for step in 0..<3_000 {
            switch Int.random(in: 0..<10) {
            case 0, 1, 2:
                if let a = store.currentAnimal { store.unlockNext(for: a, allowOutsideFocus: Bool.random()) }
            case 3, 4:
                offset += Int.random(in: 0...2)
                store.refreshDay(now: day(offset))
            case 5:
                store.setFocus(groups: Set(AnimalGroup.allCases.filter { _ in Int.random(in: 0..<4) == 0 }),
                               regions: Set(Region.allCases.filter { _ in Int.random(in: 0..<5) == 0 }))
            case 6:
                if let a = store.library.randomElement() { store.markQuizPassed(a) }
            case 7:
                if Int.random(in: 0..<40) == 0 { store.resetProgress() }
            case 8:
                store.state.units = UnitPreference.allCases.randomElement()!
            default:
                _ = (store.streak, store.dayNumber, store.journalAnimals.count, store.focusSummary)
            }
            assertConsistent(store)
            XCTAssertNotNil(store.currentAnimal, "Today went empty at step \(step)")
            if store.currentAnimal == nil { return }
        }
    }

    /// Saving and loading in a tight loop never loses or corrupts progress.
    func testRepeatedSaveAndLoad() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var store = onboarded(fileURL: url)
        for _ in 0..<100 {
            store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true)
            let expected = store.state
            store = AppStore(fileURL: url)
            XCTAssertEqual(saved(store.state), saved(expected))
        }
    }
}
