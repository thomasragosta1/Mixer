import XCTest
@testable import Fauna

/// Edge cases in the daily flow, focus and saving.
@MainActor
final class MoreStoreTests: XCTestCase {
    private let cal = Calendar.current

    private func onboarded(groups: Set<AnimalGroup> = [], regions: Set<Region> = [], fileURL: URL? = nil) -> AppStore {
        let store = AppStore(fileURL: fileURL)
        store.setFocus(groups: groups, regions: regions)
        store.completeOnboarding()
        return store
    }

    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: .now)! }

    func testDayNumberIgnoresUnlockedAnimals() {
        let store = onboarded()
        for _ in 0..<3 { store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true) }
        XCTAssertEqual(store.dayNumber, 1)
        store.refreshDay(now: day(1))
        XCTAssertEqual(store.dayNumber, 2)
    }

    func testCannotUnlockInsideAnEmptyFocus() {
        let store = onboarded(groups: [.fish], regions: [.antarctica])
        XCTAssertFalse(store.canUnlockInFocus)
        XCTAssertTrue(store.canUnlockAnywhere)
        XCTAssertNil(store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: false))
    }

    func testHasFocusAfterChoosingOne() {
        let store = AppStore(fileURL: nil)
        store.setFocus(groups: [], regions: [.asia])
        XCTAssertTrue(store.hasFocus)
        store.setFocus(groups: [], regions: [])
        XCTAssertFalse(store.hasFocus)
    }

    func testFocusIsSavedInAStableOrder() {
        let store = AppStore(fileURL: nil)
        store.setFocus(groups: [.fish, .bird, .mammal], regions: [.openOcean, .arctic])
        XCTAssertEqual(store.state.focusGroups, [.mammal, .bird, .fish])
        XCTAssertEqual(store.state.focusRegions, [.arctic, .openOcean])
    }

    func testRevisitingAnOldFriendKeepsItsHistory() {
        let store = AppStore(fileURL: nil)
        var s = AppState()
        s.hasOnboarded = true
        s.journal = store.library.enumerated().map { i, a in
            JournalEntry(animalID: a.id, date: day(-store.library.count + i), source: i == 0 ? .unlocked : .daily)
        }
        store.state = s
        store.refreshDay()
        let oldest = store.library[0].id
        XCTAssertEqual(store.currentAnimal?.id, oldest)
        let entry = store.state.journal.first { $0.animalID == oldest }
        XCTAssertEqual(entry?.source, .unlocked, "how you first met it is kept")
        XCTAssertEqual(entry.map { cal.isDateInToday($0.date) }, true, "but it moves to the top of the journal")
        XCTAssertEqual(store.state.journal.count, store.library.count)
    }

    func testTodayKeepsTheOrderAnimalsWereMet() {
        let store = onboarded()
        var expected = [store.currentAnimal!.id]
        for _ in 0..<4 { expected.append(store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true)!.id) }
        XCTAssertEqual(store.state.todayChain, expected)
        XCTAssertEqual(store.todayAnimals.map(\.id), expected)
    }

    func testMidnightRollsOver() {
        let store = onboarded()
        let first = store.currentAnimal?.id
        let midnight = cal.startOfDay(for: day(1))
        store.refreshDay(now: midnight.addingTimeInterval(-60))
        XCTAssertEqual(store.currentAnimal?.id, first, "11:59 pm is still today")
        store.refreshDay(now: midnight.addingTimeInterval(60))
        XCTAssertNotEqual(store.currentAnimal?.id, first, "12:01 am is a new day")
    }

    func testClockGoingBackwardsStaysConsistent() {
        let store = onboarded()
        store.refreshDay(now: day(5))
        store.refreshDay(now: day(2))
        XCTAssertNotNil(store.currentAnimal)
        XCTAssertEqual(Set(store.state.journal.map(\.animalID)).count, store.state.journal.count)
    }

    func testMetAndUndiscoveredCoverTheLibrary() {
        let store = onboarded()
        for _ in 0..<10 { store.unlockNext(for: store.currentAnimal!, allowOutsideFocus: true) }
        XCTAssertEqual(store.metIDs.count + store.undiscovered.count, store.library.count)
        XCTAssertTrue(Set(store.undiscovered.map(\.id)).isDisjoint(with: store.metIDs))
    }

    func testInMemoryStoreNeverTouchesDisk() {
        let store = AppStore(fileURL: nil)
        store.completeOnboarding()
        store.state.units = .imperial
        XCTAssertEqual(AppStore(fileURL: nil).state, AppState(), "a store without a file starts fresh every time")
    }

    func testFocusAndReminderSettingsPersist() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fauna-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = onboarded(groups: [.reptile], regions: [.oceania], fileURL: url)
        store.state.reminderEnabled = true
        store.state.reminderHour = 7
        store.state.reminderMinute = 45
        let reopened = AppStore(fileURL: url)
        XCTAssertEqual(reopened.focusGroups, [.reptile])
        XCTAssertEqual(reopened.focusRegions, [.oceania])
        XCTAssertTrue(reopened.state.reminderEnabled)
        XCTAssertEqual(reopened.state.reminderHour, 7)
        XCTAssertEqual(reopened.state.reminderMinute, 45)
    }

    func testDefaultStateRoundTrips() throws {
        let data = try JSONEncoder.fauna.encode(AppState())
        XCTAssertEqual(try JSONDecoder.fauna.decode(AppState.self, from: data), AppState())
    }

    func testEmptySaveFileDecodesToDefaults() throws {
        XCTAssertEqual(try JSONDecoder.fauna.decode(AppState.self, from: Data("{}".utf8)), AppState())
    }

    func testCompletingOnboardingTwiceChangesNothing() {
        let store = onboarded()
        let before = store.state.todayChain
        store.completeOnboarding()
        XCTAssertEqual(store.state.todayChain, before)
        XCTAssertEqual(store.state.journal.count, 1)
    }

    func testResettingTwiceIsSafe() {
        let store = onboarded()
        store.resetProgress()
        store.resetProgress()
        XCTAssertEqual(store.state.journal.count, 1)
        XCTAssertNotNil(store.currentAnimal)
    }

    func testFocusPoolMatchesEachKind() {
        let store = AppStore(fileURL: nil)
        for g in AnimalGroup.allCases {
            store.setFocus(groups: [g], regions: [])
            XCTAssertEqual(store.focusPool.count, store.library.filter { $0.group == g }.count, g.rawValue)
        }
    }

    func testFocusPoolMatchesEachPlace() {
        let store = AppStore(fileURL: nil)
        for r in Region.allCases {
            store.setFocus(groups: [], regions: [r])
            XCTAssertEqual(store.focusPool.count, store.library.filter { $0.regions.contains(r) }.count, r.rawValue)
        }
    }

    func testPreviewingAFocusDoesNotChangeTheSavedOne() {
        let store = AppStore(fileURL: nil)
        store.setFocus(groups: [.bird], regions: [])
        let bird = store.library.first { $0.group == .bird }!
        let mammal = store.library.first { $0.group == .mammal }!
        XCTAssertTrue(store.matchesFocus(mammal, groups: [.mammal], regions: []))
        XCTAssertFalse(store.matchesFocus(mammal))
        XCTAssertTrue(store.matchesFocus(bird))
    }

    func testFocusSummaryJoinsKindsWithOr() {
        let store = AppStore(fileURL: nil)
        store.setFocus(groups: [.mammal, .bird], regions: [])
        XCTAssertEqual(store.focusSummary, "Birds or Mammals")
    }

    func testUpcomingAnimalsNeverExceedTheQueue() {
        let store = onboarded(groups: [.fish])
        XCTAssertEqual(store.upcomingDailyAnimals(count: 30).count, store.state.queue.count)
        XCTAssertLessThan(store.state.queue.count, 30)
    }

    func testUnknownAnimalLookups() {
        let store = AppStore(fileURL: nil)
        XCTAssertNil(store.animal("unicorn"))
        XCTAssertNotNil(store.animal("okapi"))
    }

    func testNoHistoryMeansNoStreak() {
        XCTAssertEqual(AppStore(fileURL: nil).streak, 0)
        XCTAssertEqual(AppStore(fileURL: nil).dayNumber, 0)
    }

    func testDailyAnimalsStayInFocusUntilItRunsOut() {
        let store = onboarded(groups: [.fish])
        let fish = store.library.filter { $0.group == .fish }.count
        XCTAssertEqual(store.currentAnimal?.group, .fish)
        for d in 1..<fish {
            store.refreshDay(now: day(d))
            XCTAssertEqual(store.currentAnimal?.group, .fish, "day \(d)")
        }
        store.refreshDay(now: day(fish))
        XCTAssertNotNil(store.currentAnimal, "after the last fish, Fauna picks from anywhere")
        XCTAssertNotEqual(store.currentAnimal?.group, .fish)
    }
}
