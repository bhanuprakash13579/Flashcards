import Foundation

/// Builds prioritized practice queues. Pure logic — no UI, no SwiftData container access.
enum PracticeQueue {

    /// Maximum cards in one practice round across modes (keeps sessions ~5–10 min).
    static let defaultRoundSize: Int = 20

    /// Default daily new-card cap. Tunable from Settings via @AppStorage("dailyNewCardLimit").
    static let defaultDailyNewCardLimit: Int = 20

    /// Build a prioritized round.
    ///
    /// Order rules:
    /// 1. Cards already due (`nextReview <= now`) **and not new** — these are the spaced-rep
    ///    reviews that earn long-term retention. Struggling first, then by oldest review.
    /// 2. Brand-new cards (`isNew`) — capped by `dailyNewCardLimit` minus what's already been
    ///    introduced today (so the same 20 cards don't dominate every session).
    /// 3. (only if `onlyDue == false`) Everything else, oldest review first.
    ///
    /// The whole point: across multiple sessions in one day, cards already practised today are
    /// scheduled ≥ 1 day in the future by SM-2, so they naturally drop out of the queue.
    /// Combined with the new-card cap, every card gets fair rotation rather than the same 50
    /// reappearing morning-and-evening.
    static func ordered(_ cards: [Card],
                        onlyDue: Bool = true,
                        dailyNewCardLimit: Int? = nil,
                        roundSize: Int? = nil) -> [Card] {
        let now = Date()

        let dueReviews = cards
            .filter { !$0.isNew && $0.nextReview <= now }
            .sorted(by: reviewPriority)

        let cap = dailyNewCardLimit ?? defaultDailyNewCardLimit
        let alreadyIntroduced = StudyHistory.newCardsIntroducedToday()
        let remainingNewSlots = max(0, cap - alreadyIntroduced)
        let newPool = cards.filter { $0.isNew }.shuffled()
        let newCards = Array(newPool.prefix(remainingNewSlots))

        var queue = dueReviews + newCards

        if !onlyDue {
            let used = Set(queue.map(\.id))
            let leftovers = cards
                .filter { !used.contains($0.id) }
                .sorted { ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast) }
            queue.append(contentsOf: leftovers)
        }

        if let n = roundSize {
            queue = Array(queue.prefix(n))
        }
        return queue
    }

    /// True priority = struggling first, then by box ascending, then by oldest review.
    private static func reviewPriority(_ a: Card, _ b: Card) -> Bool {
        if a.isStruggling != b.isStruggling { return a.isStruggling }
        if a.box != b.box { return a.box < b.box }
        let l = a.lastReviewed ?? .distantPast
        let r = b.lastReviewed ?? .distantPast
        return l < r
    }

    /// Pick `n` distinct distractor strings from `pool` excluding `correct`.
    static func distractors(for correct: String, from pool: [String], n: Int = 3) -> [String] {
        var seen = Set<String>([correct])
        var out: [String] = []
        for s in pool.shuffled() {
            if seen.contains(s) { continue }
            seen.insert(s)
            out.append(s)
            if out.count == n { break }
        }
        return out
    }

    /// Count cards that should appear today across both buckets, given the cap.
    static func dueOrNewToday(_ cards: [Card], dailyNewCardLimit: Int? = nil) -> Int {
        ordered(cards, onlyDue: true, dailyNewCardLimit: dailyNewCardLimit, roundSize: nil).count
    }
}
