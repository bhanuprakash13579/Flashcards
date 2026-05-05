import Foundation
import UserNotifications

/// Local-only daily reminder. No server, no push tokens.
enum NotificationService {

    static let dailyReminderId = "flashcards.daily.reminder"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func currentStatus() async -> UNAuthorizationStatus {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus
    }

    /// Schedule a daily reminder at `hour:minute`. Replaces any existing daily reminder.
    /// Pass `dueCount` to show the live card count in the notification body and badge.
    static func scheduleDailyReminder(hour: Int, minute: Int, dueCount: Int = 0) async {
        await cancelDailyReminder()

        let content = UNMutableNotificationContent()
        content.title = "Time to study"
        content.body  = dueCount > 0
            ? "\(dueCount) card\(dueCount == 1 ? "" : "s") due for review today."
            : "Keep your streak alive — your flashcards are waiting."
        content.sound = .default
        content.badge = NSNumber(value: dueCount)

        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)

        let req = UNNotificationRequest(identifier: dailyReminderId, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }

    static func cancelDailyReminder() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [dailyReminderId]
        )
    }

    /// Returns the configured fire time if the daily reminder is currently scheduled.
    static func currentDailyReminderTime() async -> DateComponents? {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let req = pending.first(where: { $0.identifier == dailyReminderId }),
              let trig = req.trigger as? UNCalendarNotificationTrigger
        else { return nil }
        return trig.dateComponents
    }
}
