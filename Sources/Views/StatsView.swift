import SwiftUI
import SwiftData

struct StatsView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss

    private var boxCounts: [Int] {
        var c = Array(repeating: 0, count: 5)
        for card in deck.cards {
            let i = max(1, min(5, card.box)) - 1
            c[i] += 1
        }
        return c
    }

    private var dueOrNewToday: Int {
        PracticeQueue.dueOrNewToday(deck.cards)
    }

    private var newCount: Int { deck.cards.filter(\.isNew).count }

    private var struggling: [Card] {
        deck.cards
            .filter { $0.wrongCount > 0 }
            .sorted { $0.wrongCount > $1.wrongCount }
            .prefix(5)
            .map { $0 }
    }

    private var stale: [Card] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? .distantPast
        return deck.cards
            .filter { ($0.lastReviewed ?? $0.createdAt) < cutoff }
            .sorted { ($0.lastReviewed ?? $0.createdAt) < ($1.lastReviewed ?? $1.createdAt) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Stats computations

    /// Overall retention rate: correct / (correct + wrong) across all cards
    private var retentionRate: Double? {
        let totalCorrect = deck.cards.reduce(0) { $0 + $1.correctCount }
        let totalWrong = deck.cards.reduce(0) { $0 + $1.wrongCount }
        let total = totalCorrect + totalWrong
        guard total > 0 else { return nil }
        return Double(totalCorrect) / Double(total)
    }

    /// Projected mastery date: when all cards reach box 5 based on average progression rate
    private var projectedMasteryDate: Date? {
        let cards = deck.cards
        guard !cards.isEmpty else { return nil }
        let mastered = cards.filter { $0.box >= 5 }.count
        guard mastered < cards.count else { return nil } // all already mastered

        // Average interval for cards that have been reviewed at least once
        let reviewedCards = cards.filter { $0.repetitions > 0 }
        guard !reviewedCards.isEmpty else { return nil }

        let avgInterval = Double(reviewedCards.reduce(0) { $0 + $1.interval }) / Double(reviewedCards.count)
        let remainingCards = cards.count - mastered
        // Estimate: each remaining card needs ~(5 - avgBox) more intervals to reach box 5
        let avgBox = Double(cards.reduce(0) { $0 + $1.box }) / Double(cards.count)
        let stepsRemaining = max(1, 5.0 - avgBox)
        let daysEstimate = Int(stepsRemaining * max(avgInterval, 1.0) * Double(remainingCards) / max(Double(cards.count), 1.0))

        return Calendar.current.date(byAdding: .day, value: min(daysEstimate, 365), to: Date())
    }

    /// For each of the next 30 days, fraction of reviewed cards still retrievable (R >= 0.9).
    private var forgettingCurveData: [(day: Int, fraction: Double)] {
        let reviewed = deck.cards.filter { $0.fsrsStability != nil }
        guard !reviewed.isEmpty else { return [] }
        return (0...30).map { d in
            let frac = reviewed.filter { card in
                guard let s = card.fsrsStability, let lr = card.lastReviewed else { return false }
                let elapsed = max(0, lr.timeIntervalSinceNow / -86400) + Double(d)
                let r = pow(1 + elapsed / (9 * s), -1)
                return r >= 0.9
            }.count
            return (d, Double(frac) / Double(reviewed.count))
        }
    }

    /// Per-chapter accuracy (worst first) — only for decks that have chapter data.
    private var chapterAccuracy: [(chapter: String, accuracy: Double, count: Int)] {
        let chapters = Set(deck.cards.compactMap { c -> String? in
            let name = c.chapterName.isEmpty ? c.chapter : c.chapterName
            return name.isEmpty ? nil : name
        })
        guard !chapters.isEmpty else { return [] }
        return chapters.compactMap { ch in
            let cards = deck.cards.filter {
                let name = $0.chapterName.isEmpty ? $0.chapter : $0.chapterName
                return name == ch
            }
            let correct = cards.reduce(0) { $0 + $1.correctCount }
            let wrong   = cards.reduce(0) { $0 + $1.wrongCount }
            let total   = correct + wrong
            guard total >= 3 else { return nil }
            return (ch, Double(correct) / Double(total), total)
        }.sorted { $0.accuracy < $1.accuracy }
    }

    /// This-week vs last-week review count delta.
    private var weeklyGrowth: (thisWeek: Int, lastWeek: Int) {
        let counts = StudyHistory.recentDailyCounts(days: 14)
        let thisWeek = counts.suffix(7).reduce(0) { $0 + $1.count }
        let lastWeek = counts.prefix(7).reduce(0) { $0 + $1.count }
        return (thisWeek, lastWeek)
    }

    /// Cards that keep getting wrong: wrongCount >= 3 and failure rate > 50%.
    private var persistentErrors: [Card] {
        deck.cards.filter {
            $0.wrongCount >= 3 &&
            Double($0.wrongCount) / Double(max($0.correctCount + $0.wrongCount, 1)) > 0.5
        }
        .sorted { $0.wrongCount > $1.wrongCount }
        .prefix(8).map { $0 }
    }

    /// Difficulty breakdown: count of cards by userDifficulty label.
    private var difficultyBreakdown: [(label: String, count: Int, color: Color)] {
        [
            ("Easy",   deck.cards.filter { $0.userDifficulty == 1 }.count, Theme.success),
            ("Medium", deck.cards.filter { $0.userDifficulty == 2 }.count, .orange),
            ("Hard",   deck.cards.filter { $0.userDifficulty == 3 }.count, Theme.stretch),
            ("Unclassified", deck.cards.filter { $0.userDifficulty == 0 }.count, Color.secondary),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        NavigationStack {
            List {
                streakSection
                overviewSection
                retentionSection
                forgettingCurveSection
                activitySection
                leitnerSection
                if !chapterAccuracy.isEmpty { chapterAccuracySection }
                if !difficultyBreakdown.isEmpty { difficultySection }
                if CalibrationStore.hasEnoughData() { calibrationSection }
                if !persistentErrors.isEmpty { errorLogSection }
                if !struggling.isEmpty { strugglingSection }
                if !stale.isEmpty { staleSection }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var streakSection: some View {
        Section {
            HStack(spacing: Theme.Space.l) {
                streakCell(value: StudyHistory.currentStreak, label: "Current streak", icon: "flame.fill", tint: Theme.streak)
                Divider().frame(height: 40)
                streakCell(value: StudyHistory.longestStreak, label: "Longest", icon: "trophy.fill", tint: Theme.focus)
                Divider().frame(height: 40)
                streakCell(value: StudyHistory.todayReviews(), label: "Reviewed today", icon: "checkmark.circle.fill", tint: Theme.success)
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Text("Showing up daily is more powerful than long sessions. A 1-day grace day keeps your streak alive if you miss once.")
        }
    }

    private func streakCell(value: Int, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint)
                Text("\(value)").font(.title2).fontWeight(.bold)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var overviewSection: some View {
        Section("This deck") {
            LabeledContent("Total cards", value: "\(deck.cards.count)")
            LabeledContent("New (never seen)", value: "\(newCount)")
            LabeledContent("Up for today", value: "\(dueOrNewToday)")
            LabeledContent("Mastered (box 5)", value: "\(boxCounts[4])")
        }
    }

    private var retentionSection: some View {
        Section {
            if let rate = retentionRate {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Retention rate")
                            .font(.subheadline)
                        Text(String(format: "%.0f%%", rate * 100))
                            .font(.title).fontWeight(.bold)
                            .foregroundStyle(rate >= 0.8 ? Theme.success : rate >= 0.6 ? Theme.streak : Theme.stretch)
                    }
                    Spacer()
                    retentionGauge(rate)
                }

                if let mastery = projectedMasteryDate {
                    LabeledContent("Projected mastery") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(mastery, style: .date)
                                .font(.subheadline).fontWeight(.medium)
                            Text(mastery, style: .relative)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(.secondary)
                    Text("Start reviewing cards to see your retention rate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Performance")
        } footer: {
            if retentionRate != nil {
                Text("Retention above 80% is excellent. Projected mastery is an estimate based on your current learning pace.")
            }
        }
    }

    private func retentionGauge(_ rate: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.tertiarySystemFill), lineWidth: 6)
            Circle()
                .trim(from: 0, to: rate)
                .stroke(
                    rate >= 0.8 ? Theme.success : rate >= 0.6 ? Theme.streak : Theme.stretch,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: rate >= 0.8 ? "checkmark" : "arrow.up")
                .font(.caption2.bold())
                .foregroundStyle(rate >= 0.8 ? Theme.success : .secondary)
        }
        .frame(width: 44, height: 44)
    }

    private var difficultySection: some View {
        Section {
            ForEach(difficultyBreakdown, id: \.label) { item in
                HStack {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(item.label).font(.subheadline)
                    Spacer()
                    Text("\(item.count)").font(.subheadline).foregroundStyle(.secondary)
                    Text(String(format: "%.0f%%", Double(item.count) / Double(max(deck.cards.count, 1)) * 100))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("By difficulty tag")
        } footer: {
            Text("Flag cards during practice using the difficulty menu — helps you focus sessions on Hard cards before an exam.")
        }
    }

    @ViewBuilder
    private var forgettingCurveSection: some View {
        let data = forgettingCurveData
        if !data.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(data, id: \.day) { point in
                            VStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        point.fraction >= 0.8 ? Theme.success.opacity(0.75) :
                                        point.fraction >= 0.5 ? Theme.streak.opacity(0.75) :
                                        Theme.stretch.opacity(0.75)
                                    )
                                    .frame(height: max(3, CGFloat(point.fraction) * 60))
                                if point.day % 7 == 0 {
                                    Text("d\(point.day)").font(.system(size: 7)).foregroundStyle(.secondary)
                                } else {
                                    Text("").font(.system(size: 7))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 76)
                    .padding(.vertical, 4)
                    let todayFrac = data.first?.fraction ?? 0
                    let weekFrac = data.first(where: { $0.day == 7 })?.fraction ?? 0
                    Text(String(format: "Today: %.0f%% well-retained · In 7 days: %.0f%%", todayFrac * 100, weekFrac * 100))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Forgetting curve (next 30 days)")
            } footer: {
                Text("Fraction of reviewed cards FSRS predicts you'll still remember at the 90% threshold. Review today to keep bars green.")
            }
        }
    }

    private var activitySection: some View {
        let counts = StudyHistory.recentDailyCounts(days: 14)
        let maxCount = counts.map(\.count).max() ?? 0
        return Section {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.count > 0 ? Theme.focus.opacity(0.7) : Color(.tertiarySystemFill))
                            .frame(height: maxCount > 0
                                   ? max(4, CGFloat(day.count) / CGFloat(maxCount) * 60)
                                   : 4)
                        Text(dayLabel(day.date))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
            .padding(.vertical, 6)
        } header: {
            Text("Last 14 days")
        } footer: {
            let g = weeklyGrowth
            if g.thisWeek == 0 && g.lastWeek == 0 {
                Text("No reviews yet — start a quick round to get on the board.")
            } else if g.lastWeek == 0 {
                Text("You reviewed \(g.thisWeek) cards this week. Keep it up!")
            } else {
                let delta = g.thisWeek - g.lastWeek
                let pct   = Int(abs(Double(delta) / Double(g.lastWeek) * 100))
                if delta > 0 {
                    Text("↑ \(pct)% more than last week (\(g.thisWeek) vs \(g.lastWeek) cards). You're building momentum.")
                } else if delta < 0 {
                    Text("↓ \(pct)% fewer than last week (\(g.thisWeek) vs \(g.lastWeek)). A short session today closes the gap.")
                } else {
                    Text("Consistent with last week — \(g.thisWeek) cards reviewed. Consistency beats intensity.")
                }
            }
        }
    }

    private var leitnerSection: some View {
        Section("Spread by box") {
            ForEach(0..<5, id: \.self) { i in
                BoxBar(box: i + 1, count: boxCounts[i],
                       total: max(deck.cards.count, 1),
                       color: Color(hex: deck.colorHex))
            }
        }
    }

    private var strugglingSection: some View {
        Section("Cards that need extra work") {
            ForEach(struggling) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.front).fontWeight(.medium).lineLimit(1)
                    HStack {
                        Text("Missed \(c.wrongCount)× · Got \(c.correctCount)× · Box \(c.box)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        RatingSparkline(ratings: c.recentRatings)
                    }
                }
            }
        }
    }

    private var staleSection: some View {
        Section {
            ForEach(stale) { c in
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.front).fontWeight(.medium).lineLimit(1)
                    Text(staleSubtitle(c))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Haven't seen in a while")
        } footer: {
            Text("These resurface so you don't lose ground.")
        }
    }

    // MARK: - New sections

    private var chapterAccuracySection: some View {
        Section {
            ForEach(chapterAccuracy.prefix(10), id: \.chapter) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(item.accuracy < 0.50 ? Theme.stretch :
                              item.accuracy < 0.75 ? Color.orange : Theme.success)
                        .frame(width: 8, height: 8)
                    Text(item.chapter)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%%", item.accuracy * 100))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(item.accuracy < 0.50 ? Theme.stretch :
                                         item.accuracy < 0.75 ? Color.orange : Theme.success)
                    Text("(\(item.count))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Chapter accuracy — weakest first")
        } footer: {
            Text("Below 70% = needs more practice. Aim for green across all chapters before your exam.")
        }
    }

    @ViewBuilder
    private var calibrationSection: some View {
        let stats = CalibrationStore.load()
        let labels = [(1, "Said No"), (2, "Said Unsure"), (3, "Said Yes")]
        Section {
            ForEach(labels, id: \.0) { (key, label) in
                if let bucket = stats[key], bucket.total >= 3 {
                    HStack(spacing: 10) {
                        Text(label)
                            .font(.subheadline)
                            .frame(width: 90, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.tertiarySystemFill))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(bucket.accuracy >= 0.8 ? Theme.success :
                                          bucket.accuracy >= 0.5 ? Color.orange : Theme.stretch)
                                    .frame(width: geo.size.width * bucket.accuracy)
                            }
                        }
                        .frame(height: 8)
                        Text(String(format: "%.0f%%", bucket.accuracy * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Confidence calibration")
        } footer: {
            let yesStats = stats[3]
            if let y = yesStats, y.total >= 5 {
                Text(String(format: "When you said \"Yes\", you were right %.0f%% of the time. Perfect calibration = 100%%.", y.accuracy * 100))
            } else {
                Text("Tracks how often your confidence prediction matches the result. Data builds up as you study.")
            }
        }
    }

    private var errorLogSection: some View {
        Section {
            ForEach(persistentErrors) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.front).fontWeight(.medium).lineLimit(2)
                    HStack {
                        let failRate = Int(Double(c.wrongCount) / Double(max(c.correctCount + c.wrongCount, 1)) * 100)
                        Text("Failed \(failRate)% of the time · \(c.wrongCount) wrong · \(c.correctCount) right")
                            .font(.caption).foregroundStyle(Theme.stretch)
                        Spacer()
                        RatingSparkline(ratings: c.recentRatings)
                    }
                }
            }
        } header: {
            Text("Persistent weak spots")
        } footer: {
            Text("Cards you've got wrong more than half the time. Prioritise these in your next session.")
        }
    }

    // MARK: - Helpers

    private func staleSubtitle(_ c: Card) -> String {
        let last = c.lastReviewed ?? c.createdAt
        let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
        return "Last seen \(days) day\(days == 1 ? "" : "s") ago · Box \(c.box)"
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // single-letter weekday
        return f.string(from: date)
    }
}

/// Compact dot-row showing the last N ratings (green = correct, red = wrong).
private struct RatingSparkline: View {
    let ratings: [Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(ratings.suffix(10).enumerated()), id: \.offset) { _, r in
                Circle()
                    .fill(r >= 3 ? Theme.success : Theme.stretch)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

private struct BoxBar: View {
    let box: Int
    let count: Int
    let total: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Box \(box)").font(.subheadline).fontWeight(.medium)
                Spacer()
                Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemBackground))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.45 + 0.10 * Double(box)))
                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(total))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }
}
