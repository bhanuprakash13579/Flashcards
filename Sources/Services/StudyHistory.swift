import Foundation

/// Tracks streaks and per-day review counts in UserDefaults.
/// Lightweight — small JSON blob (last 60 days), no extra SwiftData entity.
enum StudyHistory {

    private static let countsKey = "studyHistory.dailyCounts"
    private static let lastDateKey = "studyHistory.lastDate"
    private static let streakKey = "studyHistory.currentStreak"
    private static let longestKey = "studyHistory.longestStreak"
    private static let newIntroDateKey = "studyHistory.newIntroDate"
    private static let newIntroCountKey = "studyHistory.newIntroCount"

    private static let cal = Calendar.current
    private static let isoF: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    // MARK: - Reviews

    /// Record one card answered, on a given calendar day.
    static func recordReview(on date: Date = Date()) {
        let key = isoF.string(from: cal.startOfDay(for: date))
        var dict = dailyCounts()
        dict[key, default: 0] += 1
        save(dict)
        bumpStreak(forActivityOn: date)
    }

    /// Record N cards at once (e.g. at end of session).
    static func recordReviews(_ n: Int, on date: Date = Date()) {
        guard n > 0 else { return }
        let key = isoF.string(from: cal.startOfDay(for: date))
        var dict = dailyCounts()
        dict[key, default: 0] += n
        save(dict)
        bumpStreak(forActivityOn: date)
    }

    /// Reviews per day for the last `days` days, oldest first.
    static func recentDailyCounts(days: Int = 30) -> [(date: Date, count: Int)] {
        let dict = dailyCounts()
        var result: [(Date, Int)] = []
        for offset in (0..<days).reversed() {
            guard let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { continue }
            let key = isoF.string(from: d)
            result.append((d, dict[key] ?? 0))
        }
        return result
    }

    static func todayReviews(date: Date = Date()) -> Int {
        let key = isoF.string(from: cal.startOfDay(for: date))
        return dailyCounts()[key] ?? 0
    }

    // MARK: - Streak

    static var currentStreak: Int { UserDefaults.standard.integer(forKey: streakKey) }
    static var longestStreak: Int { UserDefaults.standard.integer(forKey: longestKey) }

    private static func bumpStreak(forActivityOn date: Date) {
        let today = cal.startOfDay(for: date)
        let last = (UserDefaults.standard.object(forKey: lastDateKey) as? Date)
            .map { cal.startOfDay(for: $0) }

        var streak = UserDefaults.standard.integer(forKey: streakKey)

        if last == nil {
            streak = 1
        } else if last == today {
            // Already counted activity today; nothing to do.
        } else if let last, let dayDiff = cal.dateComponents([.day], from: last, to: today).day {
            switch dayDiff {
            case 1: streak += 1
            case 2: streak += 1   // 1-day grace: missed a day, keep streak alive.
            default: streak = 1   // Longer gap → reset.
            }
        }

        let longest = max(UserDefaults.standard.integer(forKey: longestKey), streak)
        UserDefaults.standard.set(today, forKey: lastDateKey)
        UserDefaults.standard.set(streak, forKey: streakKey)
        UserDefaults.standard.set(longest, forKey: longestKey)
    }

    // MARK: - New-card cap (per-day intro counter)

    /// How many brand-new (repetitions == 0) cards we've already shown today.
    static func newCardsIntroducedToday() -> Int {
        let today = cal.startOfDay(for: Date())
        let stored = UserDefaults.standard.object(forKey: newIntroDateKey) as? Date
        if let stored, cal.isDate(stored, inSameDayAs: today) {
            return UserDefaults.standard.integer(forKey: newIntroCountKey)
        }
        UserDefaults.standard.set(today, forKey: newIntroDateKey)
        UserDefaults.standard.set(0, forKey: newIntroCountKey)
        return 0
    }

    static func bumpNewCardsIntroduced(by n: Int) {
        guard n > 0 else { return }
        let current = newCardsIntroducedToday()
        UserDefaults.standard.set(current + n, forKey: newIntroCountKey)
    }

    // MARK: - Storage helpers

    private static func dailyCounts() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: countsKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        // Keep only the last 60 days to bound size.
        let cutoff = cal.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let cutoffKey = isoF.string(from: cutoff)
        return dict.filter { $0.key >= cutoffKey }
    }

    private static func save(_ dict: [String: Int]) {
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: countsKey)
        }
    }
}
