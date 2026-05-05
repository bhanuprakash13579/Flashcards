import Foundation

/// Builds prioritized practice queues. Pure logic — no UI, no SwiftData container access.
enum PracticeQueue {

    /// Maximum cards in one practice round across modes (keeps sessions ~5–10 min).
    static let defaultRoundSize: Int = 20

    /// Maximum brand-new cards introduced per day. Prevents cognitive overload on large decks.
    static let defaultDailyNewCardLimit: Int = 20

    /// Difficulty filter for practice sessions.
    enum CardFilter: String, CaseIterable, Identifiable {
        case all       = "All cards"
        case dueOnly   = "Due only"
        case struggling = "Struggling"
        case newOnly   = "New only"
        case easyOnly  = "Easy cards"
        case mediumOnly = "Medium cards"
        case hardOnly  = "Hard cards"
        case unclassifiedOnly = "Unclassified"
        var id: String { rawValue }
    }

    /// Build a prioritized round.
    ///
    /// Order rules:
    /// 0. (when neverForgetEnabled) Hard / struggling cards not yet reviewed today — always first.
    /// 1. Cards already due (`nextReview <= now`) **and not new** — these are the spaced-rep
    ///    reviews that earn long-term retention. Struggling first, then by oldest review.
    /// 2. Brand-new cards (`isNew`) — capped by `dailyNewCardLimit` minus what's already been
    ///    introduced today (so the same 20 cards don't dominate every session).
    /// 3. (only if `onlyDue == false`) Everything else, oldest review first.
    static func ordered(_ cards: [Card],
                        onlyDue: Bool = true,
                        roundSize: Int? = nil,
                        filter: CardFilter = .all,
                        dailyNewCardLimit: Int = defaultDailyNewCardLimit,
                        neverForgetEnabled: Bool = false) -> [Card] {
        // Apply filter first
        let filtered: [Card]
        switch filter {
        case .all:
            filtered = cards
        case .dueOnly:
            let now = Date()
            filtered = cards.filter { $0.nextReview <= now }
        case .struggling:
            filtered = cards.filter { $0.isStruggling }
        case .newOnly:
            filtered = cards.filter { $0.isNew }
        case .easyOnly:
            filtered = cards.filter { $0.userDifficulty == 1 }
        case .mediumOnly:
            filtered = cards.filter { $0.userDifficulty == 2 }
        case .hardOnly:
            filtered = cards.filter { $0.userDifficulty == 3 }
        case .unclassifiedOnly:
            filtered = cards.filter { $0.userDifficulty == 0 }
        }

        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)

        // Never-Forget bucket: Hard/struggling cards not yet seen today → always at front.
        let neverForgetCards: [Card]
        if neverForgetEnabled {
            neverForgetCards = filtered
                .filter { ($0.userDifficulty == 3 || $0.isStruggling) && !$0.isNew }
                .filter { ($0.lastReviewed ?? .distantPast) < todayStart }
                .sorted(by: reviewPriority)
        } else {
            neverForgetCards = []
        }
        let neverForgetIDs = Set(neverForgetCards.map(\.id))

        let dueReviews = filtered
            .filter { !$0.isNew && $0.nextReview <= now && !neverForgetIDs.contains($0.id) }
            .sorted(by: reviewPriority)

        let alreadyIntroducedToday = StudyHistory.newCardsIntroducedToday()
        let remainingNewSlots = max(0, dailyNewCardLimit - alreadyIntroducedToday)
        let allNewCards = filtered.filter { $0.isNew }.shuffled()
        let newCards = Array(allNewCards.prefix(remainingNewSlots))
        // IDs of new cards beyond today's cap — must never enter via the leftovers bucket.
        let overCapNewIDs = Set(allNewCards.dropFirst(remainingNewSlots).map(\.id))

        var queue = neverForgetCards + dueReviews + newCards

        if !onlyDue {
            let used = Set(queue.map(\.id))
            let leftovers = filtered
                .filter { !used.contains($0.id) && !overCapNewIDs.contains($0.id) }
                .sorted { ($0.lastReviewed ?? .distantPast) < ($1.lastReviewed ?? .distantPast) }
            queue.append(contentsOf: leftovers)
        }

        if let n = roundSize {
            queue = Array(queue.prefix(n))
        }
        // Preserve priority order: only shuffle within equal-priority groups.
        // Struggling due reviews stay at front; new cards (already shuffled) follow.
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
    /// Prefers candidates of the same semantic type (article, section, currency,
    /// percentage, number, act) and similar length so the question remains
    /// genuinely challenging rather than trivially easy.
    static func distractors(for correct: String, from pool: [String], n: Int = 3) -> [String] {
        let seen = Set<String>([correct])
        let candidates = pool.filter { !seen.contains($0) }
        let correctType = answerType(correct)

        // Split into same-type and different-type, score each by keyword similarity
        let sameType = candidates
            .filter { answerType($0) == correctType }
            .map { ($0, distractorScore($0, against: correct)) }
            .sorted { $0.1 > $1.1 }

        let diffType = candidates
            .filter { answerType($0) != correctType }
            .map { ($0, distractorScore($0, against: correct)) }
            .sorted { $0.1 > $1.1 }

        // Shuffle within the top portion of same-type to vary across rounds,
        // then pad with different-type only when same-type runs out.
        let topSame = Array(sameType.prefix(max(n * 2, 6))).map(\.0).shuffled()
        let topDiff = Array(diffType.prefix(max(n * 2, 6))).map(\.0).shuffled()

        var out: [String] = []
        var used = seen
        for s in topSame + topDiff {
            if used.contains(s) { continue }
            used.insert(s)
            out.append(s)
            if out.count == n { return out }
        }
        return out
    }

    // MARK: - Distractor scoring (private)

    /// Returns a score ≥ 0 for how plausible `candidate` is as a wrong answer
    /// when the right answer is `correct`. Higher = more plausible = better distractor.
    private static func distractorScore(_ candidate: String, against correct: String) -> Int {
        var score = 0

        // Same semantic type is the strongest signal
        if answerType(candidate) == answerType(correct) { score += 10 }

        // Shared meaningful keywords (length > 3, ignoring common stop words)
        let stopWords: Set<String> = ["that","this","with","from","have","been","more","than","under","each","every","such","shall","any","all","are","the","and","for","per","not","its","was","has","but","also"]
        let correctWords = tokenise(correct).filter { $0.count > 3 && !stopWords.contains($0) }
        let candWords    = Set(tokenise(candidate))
        let shared = correctWords.filter { candWords.contains($0) }
        score += shared.count * 3

        // Similar character length (within 0.4×–2.5× of the correct answer)
        let ratio = Double(candidate.count) / Double(max(correct.count, 1))
        if ratio >= 0.4 && ratio <= 2.5 { score += 2 }

        return score
    }

    private static func tokenise(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private enum AnswerType: Equatable {
        case article, section, currency, percentage, act, year, numeric, general
    }

    private static func answerType(_ s: String) -> AnswerType {
        let lower = s.lowercased()
        // Test most-specific patterns first
        if lower.range(of: #"\barticle\s*\d"#, options: .regularExpression) != nil { return .article }
        if lower.range(of: #"\b(section|s\.)\s*\d"#, options: .regularExpression) != nil { return .section }
        if s.contains("₹") || lower.contains("rs.") || lower.contains("inr") { return .currency }
        if s.contains("%") { return .percentage }
        if lower.hasSuffix("act") || lower.hasSuffix("code") || lower.hasSuffix("act,") { return .act }
        // Four-digit year anywhere
        if s.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) != nil { return .year }
        // Mostly numeric (digits make up > 30% of characters)
        let digits = s.filter(\.isNumber)
        if Double(digits.count) / Double(max(s.count, 1)) > 0.3 { return .numeric }
        return .general
    }

    /// Count cards that should appear today across both buckets, given the cap.
    static func dueOrNewToday(_ cards: [Card]) -> Int {
        ordered(cards, onlyDue: true, roundSize: nil).count
    }
}
