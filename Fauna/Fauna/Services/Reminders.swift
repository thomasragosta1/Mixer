import Foundation
import UserNotifications

/// Schedules the daily "meet today's animal" notification for the next few weeks.
///
/// Each notification names the animal that day will bring (the head of the queue), so the
/// schedule is rebuilt whenever the queue changes: on launch, after an unlock, and after a
/// focus change. Without that, the generic text is used.
@MainActor
enum Reminders {
    private static let prefix = "fauna.daily."
    private static let days = 30

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func reschedule(_ store: AppStore) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let state = store.state
        guard state.hasOnboarded, state.reminderEnabled else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let upcoming = store.upcomingDailyAnimals(count: days)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        for offset in 1...days {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            var parts = cal.dateComponents([.year, .month, .day], from: day)
            parts.hour = state.reminderHour
            parts.minute = state.reminderMinute

            let content = UNMutableNotificationContent()
            if offset - 1 < upcoming.count {
                let animal = upcoming[offset - 1]
                content.title = "Meet the \(animal.name)"
                content.body = "\(animal.tagline). \(animal.readingMinutes)-minute read."
            } else {
                content.title = "A new animal is waiting"
                content.body = "Today's creature is ready for you."
            }
            content.sound = .default
            content.threadIdentifier = "daily-animal"

            let request = UNNotificationRequest(
                identifier: prefix + AppStore.dayKey(for: day),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            try? await center.add(request)
        }
    }
}
