import SwiftUI
import SwiftData

struct StatsView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit

    private var boxCounts: [Int] {
        var c = Array(repeating: 0, count: 5)
        for card in deck.cards {
            let i = max(1, min(5, card.box)) - 1
            c[i] += 1
        }
        return c
    }

    private var dueOrNewToday: Int {
        PracticeQueue.dueOrNewToday(deck.cards, dailyNewCardLimit: dailyNewCardLimit)
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

    var body: some View {
        NavigationStack {
            List {
                streakSection
                overviewSection
                activitySection
                leitnerSection
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

    private var activitySection: some View {
        let counts = StudyHistory.recentDailyCounts(days: 14)
        let max = counts.map(\.count).max() ?? 0
        return Section {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(counts.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(day.count > 0 ? Theme.focus.opacity(0.7) : Color(.tertiarySystemFill))
                            .frame(height: max > 0
                                   ? max(4, CGFloat(day.count) / CGFloat(max) * 60)
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
            if max == 0 {
                Text("No reviews yet — start a quick round to get on the board.")
            } else {
                Text("Tall bars = bigger study days. Consistency beats intensity.")
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.front).fontWeight(.medium).lineLimit(1)
                    Text("Missed \(c.wrongCount)× · Got \(c.correctCount)× · Box \(c.box)")
                        .font(.caption).foregroundStyle(.secondary)
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
