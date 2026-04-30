import Foundation

/// SM-2 (SuperMemo 2) algorithm — Wozniak 1985, public domain.
/// We use it lightly: quality 0...5 grades a recall attempt.
/// In our 2-button UI we map: wrong=2, right=4, easy=5.
enum SpacedRepetition {

    static let minimumEase: Double = 1.3
    static let maximumIntervalDays: Int = 365

    /// Mutates the card's `ease`, `interval`, `repetitions`, `nextReview`, `lastReviewed`.
    static func apply(quality q: Int, to card: Card) {
        let quality = max(0, min(5, q))
        let now = Date()

        if quality < 3 {
            // Lapse: drop back to short interval, lose ease.
            card.repetitions = 0
            card.interval = 1
        } else {
            card.repetitions += 1
            switch card.repetitions {
            case 1:  card.interval = 1
            case 2:  card.interval = 6
            default:
                let scaled = Double(card.interval) * card.ease
                card.interval = min(maximumIntervalDays, max(1, Int(scaled.rounded())))
            }
        }

        // Standard SM-2 ease update.
        let diff = 5.0 - Double(quality)
        let delta = 0.1 - diff * (0.08 + diff * 0.02)
        card.ease = max(minimumEase, card.ease + delta)

        card.lastReviewed = now
        card.nextReview = Calendar.current.date(byAdding: .day, value: card.interval, to: now) ?? now
    }
}
