import Foundation
import Observation

/// Everything the app remembers between launches.
struct AppState: Codable, Equatable {
    var hasOnboarded = false
    var focusGroups: [AnimalGroup] = []
    var focusRegions: [Region] = []
    var reminderEnabled = false
    var reminderHour = 8
    var reminderMinute = 0
    /// Upcoming animals in order. Tomorrow's animal is the head of the queue.
    var queue: [String] = []
    /// "yyyy-MM-dd" of the day `todayChain` belongs to.
    var dayKey = ""
    /// Animals met today: the daily one first, then any unlocked with a quiz.
    var todayChain: [String] = []
    var journal: [JournalEntry] = []
    var quizPassedIDs: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppState()
        hasOnboarded = try c.decodeIfPresent(Bool.self, forKey: .hasOnboarded) ?? d.hasOnboarded
        focusGroups = (try? c.decodeIfPresent([AnimalGroup].self, forKey: .focusGroups)) ?? d.focusGroups
        focusRegions = (try? c.decodeIfPresent([Region].self, forKey: .focusRegions)) ?? d.focusRegions
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? d.reminderEnabled
        reminderHour = try c.decodeIfPresent(Int.self, forKey: .reminderHour) ?? d.reminderHour
        reminderMinute = try c.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? d.reminderMinute
        queue = try c.decodeIfPresent([String].self, forKey: .queue) ?? d.queue
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? d.dayKey
        todayChain = try c.decodeIfPresent([String].self, forKey: .todayChain) ?? d.todayChain
        journal = try c.decodeIfPresent([JournalEntry].self, forKey: .journal) ?? d.journal
        quizPassedIDs = try c.decodeIfPresent([String].self, forKey: .quizPassedIDs) ?? d.quizPassedIDs
    }
}

struct JournalEntry: Codable, Hashable, Identifiable {
    enum Source: String, Codable { case daily, unlocked }
    let animalID: String
    let date: Date
    let source: Source
    var id: String { animalID }
}

@MainActor
@Observable
final class AppStore {
    let library: [Animal]
    private let byID: [String: Animal]
    private let fileURL: URL?

    private var stateStorage: AppState

    /// Every write is saved to disk.
    var state: AppState {
        get { stateStorage }
        set {
            guard newValue != stateStorage else { return }
            stateStorage = newValue
            persist()
        }
    }

    /// Selected tab, so any screen can send the reader somewhere else.
    var selectedTab: Tab = .today

    enum Tab: Hashable { case today, journal, focus }

    init(library: [Animal] = AnimalLibrary.load(), fileURL: URL? = AppStore.defaultFileURL) {
        self.library = library
        self.byID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.fauna.decode(AppState.self, from: data) {
            stateStorage = saved
        } else {
            stateStorage = AppState()
        }
    }

    static var defaultFileURL: URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent("fauna-state.json")
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder.fauna.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - Lookups

    func animal(_ id: String) -> Animal? { byID[id] }

    var todayAnimals: [Animal] { state.todayChain.compactMap { byID[$0] } }
    var currentAnimal: Animal? { todayAnimals.last }

    var metIDs: Set<String> { Set(state.journal.map(\.animalID)) }

    struct JournalItem: Identifiable {
        let entry: JournalEntry
        let animal: Animal
        var id: String { entry.id }
    }

    var journalAnimals: [JournalItem] {
        state.journal.sorted { $0.date > $1.date }.compactMap { entry in
            byID[entry.animalID].map { JournalItem(entry: entry, animal: $0) }
        }
    }

    var undiscovered: [Animal] {
        let met = metIDs
        return library.filter { !met.contains($0.id) }
    }

    func hasPassedQuiz(_ animal: Animal) -> Bool { state.quizPassedIDs.contains(animal.id) }

    /// The ordinal of today's daily animal: "Day 12" means the twelfth day you've opened Fauna.
    var dayNumber: Int {
        Set(state.journal.filter { $0.source == .daily }.map { Self.dayKey(for: $0.date) }).count
    }

    var streak: Int {
        let days = Set(state.journal.map { Self.dayKey(for: $0.date) })
        let cal = Calendar.current
        var day = cal.startOfDay(for: .now)
        if !days.contains(Self.dayKey(for: day)) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while days.contains(Self.dayKey(for: day)) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    // MARK: - Focus

    var focusGroups: Set<AnimalGroup> { Set(state.focusGroups) }
    var focusRegions: Set<Region> { Set(state.focusRegions) }

    func matchesFocus(_ animal: Animal, groups: Set<AnimalGroup>? = nil, regions: Set<Region>? = nil) -> Bool {
        let g = groups ?? focusGroups
        let r = regions ?? focusRegions
        return (g.isEmpty || g.contains(animal.group)) && (r.isEmpty || !r.isDisjoint(with: animal.regions))
    }

    var focusPool: [Animal] { library.filter { matchesFocus($0) } }

    var unmetInFocus: [Animal] {
        let met = metIDs
        return focusPool.filter { !met.contains($0.id) }
    }

    var hasFocus: Bool { !state.focusGroups.isEmpty || !state.focusRegions.isEmpty }

    var focusSummary: String {
        let groups = state.focusGroups.sorted { $0.title < $1.title }.map(\.title)
        let regions = state.focusRegions.sorted { $0.title < $1.title }.map(\.shortTitle)
        switch (groups.isEmpty, regions.isEmpty) {
        case (true, true): return "Every animal, everywhere"
        case (false, true): return groups.formatted(.list(type: .or))
        case (true, false): return "Anything in " + regions.formatted(.list(type: .or))
        case (false, false): return groups.formatted(.list(type: .or)) + " in " + regions.formatted(.list(type: .or))
        }
    }

    func setFocus(groups: Set<AnimalGroup>, regions: Set<Region>) {
        state.focusGroups = AnimalGroup.allCases.filter(groups.contains)
        state.focusRegions = Region.allCases.filter(regions.contains)
        rebuildQueue()
    }

    // MARK: - Daily flow

    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Assigns today's animal when the date has changed (or none was ever assigned).
    func refreshDay(now: Date = .now) {
        guard state.hasOnboarded else { return }
        let key = Self.dayKey(for: now)
        guard key != state.dayKey || state.todayChain.isEmpty else { return }
        var next = state
        next.dayKey = key
        next.todayChain = []
        if let id = popNext(in: &next, allowOutsideFocus: true) {
            next.todayChain = [id]
            record(id, source: .daily, date: now, in: &next)
        }
        state = next
    }

    /// Whether another animal can be unlocked inside the reader's focus.
    var canUnlockInFocus: Bool { !unmetInFocus.isEmpty }
    var canUnlockAnywhere: Bool { !undiscovered.isEmpty }

    /// Called after a passed quiz. Returns the newly unlocked animal.
    @discardableResult
    func unlockNext(for passed: Animal, allowOutsideFocus: Bool) -> Animal? {
        var next = state
        if !next.quizPassedIDs.contains(passed.id) { next.quizPassedIDs.append(passed.id) }
        guard let id = popNext(in: &next, allowOutsideFocus: allowOutsideFocus, unmetOnly: true) else {
            state = next
            return nil
        }
        next.todayChain.append(id)
        record(id, source: .unlocked, date: .now, in: &next)
        state = next
        return byID[id]
    }

    func completeOnboarding() {
        var next = state
        next.hasOnboarded = true
        state = next
        rebuildQueue()
        refreshDay()
    }

    func resetProgress() {
        let keep = state
        var fresh = AppState()
        fresh.hasOnboarded = true
        fresh.focusGroups = keep.focusGroups
        fresh.focusRegions = keep.focusRegions
        fresh.reminderEnabled = keep.reminderEnabled
        fresh.reminderHour = keep.reminderHour
        fresh.reminderMinute = keep.reminderMinute
        state = fresh
        rebuildQueue()
        refreshDay()
    }

    /// Animals the next few daily reminders will introduce, in order (tomorrow first).
    func upcomingDailyAnimals(count: Int) -> [Animal] {
        state.queue.prefix(count).compactMap { byID[$0] }
    }

    // MARK: - Queue

    private func rebuildQueue() {
        var next = state
        let met = metIDs.union(next.todayChain)
        next.queue = library.filter { matchesFocus($0) && !met.contains($0.id) }.map(\.id).shuffled()
        state = next
    }

    private func popNext(in s: inout AppState, allowOutsideFocus: Bool, unmetOnly: Bool = false) -> String? {
        let met = Set(s.journal.map(\.animalID)).union(s.todayChain)
        s.queue.removeAll { met.contains($0) || byID[$0] == nil }
        if s.queue.isEmpty {
            let groups = Set(s.focusGroups), regions = Set(s.focusRegions)
            s.queue = library.filter { matchesFocus($0, groups: groups, regions: regions) && !met.contains($0.id) }
                .map(\.id).shuffled()
        }
        if !s.queue.isEmpty { return s.queue.removeFirst() }
        guard allowOutsideFocus else { return nil }
        if let any = library.filter({ !met.contains($0.id) }).randomElement() { return any.id }
        guard !unmetOnly else { return nil }
        // Every animal has been met: revisit the one seen longest ago.
        return s.journal.sorted { $0.date < $1.date }.first { !s.todayChain.contains($0.animalID) }?.animalID
    }

    private func record(_ id: String, source: JournalEntry.Source, date: Date, in s: inout AppState) {
        if let i = s.journal.firstIndex(where: { $0.animalID == id }) {
            s.journal[i] = JournalEntry(animalID: id, date: date, source: s.journal[i].source)
        } else {
            s.journal.append(JournalEntry(animalID: id, date: date, source: source))
        }
    }
}

extension JSONEncoder {
    static let fauna: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let fauna: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - Demo data for screenshots and previews

extension AppStore {
    /// An in-memory store with a few weeks of history, used by `-FaunaDemo` and previews.
    static func demo(todayID: String = "red-panda") -> AppStore {
        let store = AppStore(fileURL: nil)
        var s = AppState()
        s.hasOnboarded = true
        s.reminderEnabled = true
        let past = ["axolotl", "atlantic-puffin", "snow-leopard", "monarch-butterfly", "okapi",
                    "platypus", "common-loon", "whale-shark", "luna-moth", "jaguar", "kakapo"]
        let cal = Calendar.current
        for (i, id) in past.enumerated() {
            let date = cal.date(byAdding: .day, value: -(past.count - i), to: .now)!
            s.journal.append(JournalEntry(animalID: id, date: date, source: .daily))
        }
        s.quizPassedIDs = ["axolotl", "snow-leopard", "okapi", "platypus", "whale-shark", "kakapo"]
        s.dayKey = dayKey(for: .now)
        s.todayChain = [todayID]
        s.journal.append(JournalEntry(animalID: todayID, date: .now, source: .daily))
        let met = Set(s.journal.map(\.animalID))
        s.queue = store.library.map(\.id).filter { !met.contains($0) }
        store.state = s
        return store
    }
}
