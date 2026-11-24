import UIKit

/// Keeps Fauna usable without a connection.
///
/// Article text for every animal is always on the device (bundled, or a newer published
/// library saved by ContentSync). Photos and range maps are the parts that need the network,
/// so this prepares them ahead of time for the next `target` animals the reader is likely to
/// meet: today's, then the queue, then the rest. That keeps at least 30 unmet animals fully
/// readable offline at all times.
@MainActor
enum OfflineLibrary {
    /// How many upcoming animals to keep ready. Comfortably above the 30-animal minimum, so a
    /// reader who unlocks several in a row offline still has plenty left.
    static let target = 40

    private static var running: Task<Void, Never>?

    /// Checks for newly published animals (at most every few hours), then tops up the offline set.
    static func refresh(_ store: AppStore, force: Bool = false) async {
        if let update = await ContentSync.check(force: force) {
            if let photos = update.photos { await WikiImages.shared.updateSources(from: photos) }
            if let animals = update.animals {
                store.applyLibrary(animals)
                await Reminders.reschedule(store)
            }
        }
        prepare(store)
    }

    /// Downloads photos and maps for the upcoming animals that don't have them yet. Runs in the
    /// background, one animal at a time; calling it again while it runs does nothing.
    static func prepare(_ store: AppStore) {
        guard running == nil else { return }
        let animals = store.upcomingForOffline(count: target)
        let mapSize = CGSize(width: UIScreen.main.bounds.width - 44, height: 210)
        running = Task(priority: .utility) {
            await WikiImages.shared.makeAvailableOffline(animals.map(\.wikipediaTitle))
            await RangeSnapshots.shared.prefetch(animals, size: mapSize)
            running = nil
        }
    }

    /// How many unmet animals can be read with photos right now, without a connection.
    static func readyCount(_ store: AppStore) -> Int {
        let met = store.metIDs
        return store.library.filter { !met.contains($0.id) && WikiImages.shared.isAvailableOffline($0.wikipediaTitle) }.count
    }
}
