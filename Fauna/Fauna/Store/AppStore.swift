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
    /// The setting for all units at once.
    var units: UnitPreference = .automatic
    /// Per-kind choices that override `units`; nil follows it.
    var lengthUnits: UnitPreference? = nil
    var weightUnits: UnitPreference? = nil
    var distanceUnits: UnitPreference? = nil

    init() {}

    func unitOverride(_ kind: MeasureKind) -> UnitPreference? {
        switch kind {
        case .length: lengthUnits
        case .weight: weightUnits
        case .distance: distanceUnits
        }
    }

    mutating func setUnitOverride(_ kind: MeasureKind, _ value: UnitPreference?) {
        switch kind {
        case .length: lengthUnits = value
        case .weight: weightUnits = value
        case .distance: distanceUnits = value
        }
    }

    /// Sets every kind at once, clearing the per-kind choices.
    mutating func setAllUnits(_ value: UnitPreference) {
        units = value
        for k in MeasureKind.allCases { setUnitOverride(k, nil) }
    }

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
        units = (try? c.decodeIfPresent(UnitPreference.self, forKey: .units)) ?? d.units
        lengthUnits = (try? c.decodeIfPresent(UnitPreference.self, forKey: .lengthUnits)) ?? nil
        weightUnits = (try? c.decodeIfPresent(UnitPreference.self, forKey: .weightUnits)) ?? nil
        distanceUnits = (try? c.decodeIfPresent(UnitPreference.self, forKey: .distanceUnits)) ?? nil
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
    /// Every animal Fauna knows about: the bundled library, or a newer one published since.
    private(set) var library: [Animal]
    private var byID: [String: Animal]
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

    init(library: [Animal] = ContentSync.initialLibrary(), fileURL: URL? = AppStore.defaultFileURL) {
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

    nonisolated static var defaultFileURL: URL? {
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

    func usesImperial(_ kind: MeasureKind) -> Bool { (state.unitOverride(kind) ?? state.units).usesImperial }

    var imperialKinds: Set<MeasureKind> { Set(MeasureKind.allCases.filter { usesImperial($0) }) }

    /// Text with measurements shown in the reader's preferred units.
    func measured(_ text: String) -> String { UnitText.localize(text, imperial: imperialKinds) }

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

    /// Journal animals whose quiz hasn't been passed yet (never taken, or taken and missed).
    var quizzesToTake: [JournalItem] { journalAnimals.filter { !hasPassedQuiz($0.animal) } }

    /// Journal animals whose quiz has been passed.
    var quizzesCompleted: [JournalItem] { journalAnimals.filter { hasPassedQuiz($0.animal) } }

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
        // Also re-pick when today's animal no longer exists (an update renamed or removed it),
        // so Today is never left empty until midnight.
        guard key != state.dayKey || todayAnimals.isEmpty else { return }
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

    /// The animal that comes next, whether unlocked now or arriving tomorrow. Reserving it at
    /// the front of the queue means the blurred preview is exactly the animal that follows.
    @discardableResult
    func reserveNext() -> Animal? {
        var next = state
        let anywhere = !canUnlockInFocus
        guard let id = popNext(in: &next, allowOutsideFocus: anywhere, unmetOnly: true) else { return nil }
        next.queue.insert(id, at: 0)
        if next != state { state = next }
        return byID[id]
    }

    /// The reserved next animal, if there is one and it hasn't been met.
    var reservedNext: Animal? {
        let met = metIDs.union(state.todayChain)
        return state.queue.first { !met.contains($0) && byID[$0] != nil }.flatMap { byID[$0] }
    }

    /// Today's animal has been quizzed and the reader chose to wait: the next one is kept
    /// blurred until tomorrow (or until they unlock it now).
    var isWaitingForTomorrow: Bool {
        guard let current = currentAnimal, hasPassedQuiz(current), canUnlockAnywhere else { return false }
        return reservedNext != nil
    }

    /// Unlocks the reserved animal now instead of tomorrow.
    @discardableResult
    func unlockReservedNow() -> Animal? {
        guard let current = currentAnimal else { return nil }
        return unlockNext(for: current, allowOutsideFocus: !canUnlockInFocus)
    }

    func markQuizPassed(_ animal: Animal) {
        guard !state.quizPassedIDs.contains(animal.id) else { return }
        state.quizPassedIDs.append(animal.id)
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
        fresh.units = keep.units
        fresh.lengthUnits = keep.lengthUnits
        fresh.weightUnits = keep.weightUnits
        fresh.distanceUnits = keep.distanceUnits
        state = fresh
        rebuildQueue()
        refreshDay()
    }

    // MARK: - Library updates and offline use

    /// Switches to a newly published library. New animals join the end of the queue (shuffled,
    /// if they match the focus); animals that no longer exist leave it. The journal is kept as
    /// is: entries for removed animals are simply not shown.
    func applyLibrary(_ animals: [Animal]) {
        guard !animals.isEmpty, animals != library else { return }
        library = animals
        byID = Dictionary(animals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next = state
        next.queue.removeAll { byID[$0] == nil }
        let known = Set(next.queue).union(next.journal.map(\.animalID)).union(next.todayChain)
        next.queue += animals.filter { !known.contains($0.id) && matchesFocus($0) }.map(\.id).shuffled()
        state = next
        refreshDay()
    }

    /// The animals most likely to be read next, in order: today's, then the queue, then any
    /// other unmet animals. Their photos and maps are prepared ahead so Fauna works offline.
    func upcomingForOffline(count: Int) -> [Animal] {
        var ids = Array(state.todayChain.suffix(1)) + state.queue
        let met = metIDs
        ids += library.filter { !met.contains($0.id) && matchesFocus($0) }.map(\.id)
        ids += library.filter { !met.contains($0.id) }.map(\.id)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.compactMap { byID[$0] }.prefix(count).map { $0 }
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
