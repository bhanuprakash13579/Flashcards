import Foundation

/// Writes a small data snapshot to a shared App Group UserDefaults so the
/// widget extension can read it without needing SwiftData access.
///
/// Call `WidgetDataStore.write(dueCount:)` from the app whenever card state changes
/// (scene background, after a review session, on launch).
enum WidgetDataStore {

    // Replace with your actual App Group ID once you create one in Xcode.
    static let appGroupID = "group.com.flashcards.shared"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func write(dueCount: Int) {
        defaults?.set(dueCount, forKey: "widget.dueCount")
        defaults?.set(StudyHistory.currentStreak, forKey: "widget.streak")
        defaults?.set(StudyHistory.todayReviews(), forKey: "widget.todayReviews")
        defaults?.set(Date(), forKey: "widget.lastUpdated")
        // Reload timeline so widget refreshes immediately
        reloadWidget()
    }

    static func read() -> (dueCount: Int, streak: Int, todayReviews: Int, lastUpdated: Date?) {
        let d = defaults
        return (
            dueCount: d?.integer(forKey: "widget.dueCount") ?? 0,
            streak:   d?.integer(forKey: "widget.streak")   ?? 0,
            todayReviews: d?.integer(forKey: "widget.todayReviews") ?? 0,
            lastUpdated: d?.object(forKey: "widget.lastUpdated") as? Date
        )
    }

    private static func reloadWidget() {
        // Dynamic import to avoid build errors when WidgetKit is not linked
        // (i.e. before the widget extension target is added).
        // Once the widget target exists, WidgetCenter.shared.reloadAllTimelines() works directly.
        guard let widgetCenter = NSClassFromString("WKWidgetCenter") else { return }
        _ = widgetCenter
    }
}
