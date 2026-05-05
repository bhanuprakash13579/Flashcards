import Foundation

/// FSRS-4.5 (Free Spaced Repetition Scheduler) — Jarrett Ye, 2022.
/// Replaces SM-2 as the primary scheduling algorithm.
///
/// Memory model: two parameters per card
///   S (Stability)  — days until retrievability drops to 90 %
///   D (Difficulty) — 1 (very easy) to 10 (very hard)
///
/// Rating scale (matches our UI mapping):
///   1 = Again   (total blackout)
///   2 = Hard    (wrong / very hard) ← our "Hard" button
///   3 = Good    (correct with effort)
///   4 = Easy    (correct, normal)   ← our "Got it" button
///   5 = Perfect (very easy)         ← our "Easy" button (quality=5)
///
/// References: https://github.com/open-spaced-repetition/fsrs4anki
enum FSRS {

    // MARK: - Default weights (FSRS-4.5, trained on 20M+ reviews)

    static let w: [Double] = [
        0.4072, 1.1829, 3.1262, 15.4722,
        7.2102, 0.5316, 1.0651, 0.0589,
        1.5330, 0.1544, 1.0071, 1.9395,
        0.1100, 0.2900, 2.2700, 0.0500, 2.9898
    ]

    static var requestRetention: Double {
        let v = UserDefaults.standard.double(forKey: "fsrsTargetRetention")
        return v > 0 ? min(0.97, max(0.70, v)) : 0.90
    }
    static let maximumInterval: Int = 36500     // ~100 years

    // MARK: - Public entry point

    /// Mutates S, D, interval, repetitions, nextReview, lastReviewed on the card.
    static func apply(rating rawRating: Int, to card: Card) {
        // Map our 0-5 quality scale to FSRS 1-4 rating
        let r = clampRating(rawRating)
        let now = Date()

        if card.fsrsStability == nil {
            // First review — initialise S and D from first-rating tables
            let (s, d) = initialMemory(rating: r)
            card.fsrsStability    = s
            card.fsrsDifficulty   = d
            card.repetitions      = 1
            card.interval         = 1
        } else {
            // Guard handles corrupt state where stability is set but difficulty is nil
            guard let s = card.fsrsStability, let d = card.fsrsDifficulty else {
                let (s, d) = initialMemory(rating: r)
                card.fsrsStability  = s
                card.fsrsDifficulty = d
                card.repetitions    = 1
                card.interval       = 1
                card.lastReviewed   = now
                card.nextReview     = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                card.ease           = max(1.3, 5.0 - (d - 1) * 0.5)
                return
            }
            let elapsed = max(1, daysBetween(card.lastReviewed ?? now, now))
            let retrievability = pow(1 + elapsed / (9 * s), -1)

            let newD = nextDifficulty(d: d, rating: r)
            let newS: Double
            if r == 1 {
                newS = nextStabilityAfterForgetting(d: newD, s: s, r: retrievability)
            } else {
                newS = nextStabilityAfterRecall(d: newD, s: s, r: retrievability, rating: r)
            }

            card.fsrsDifficulty   = newD
            card.fsrsStability    = newS
            card.repetitions     += 1
            card.interval         = nextInterval(stability: newS)
        }

        card.lastReviewed = now
        card.nextReview   = Calendar.current.date(
            byAdding: .day, value: card.interval, to: now
        ) ?? now
        // Keep ease in plausible SM-2 range so legacy code doesn't break
        card.ease = max(1.3, 5.0 - ((card.fsrsDifficulty ?? 7.0) - 1) * 0.5)
    }

    // MARK: - Retrievability (public, used for forgetting curve display)

    /// Probability (0–1) of remembering the card right now.
    static func retrievability(for card: Card) -> Double {
        guard let s = card.fsrsStability, let lr = card.lastReviewed else { return 0 }
        let elapsed = max(0, daysBetween(lr, Date()))
        return pow(1 + elapsed / (9 * s), -1)
    }

    // MARK: - Internals

    private static func clampRating(_ q: Int) -> Int {
        // Map quality 0-5 → FSRS rating 1-4
        switch q {
        case 0, 1, 2: return 1   // Again
        case 3:        return 2   // Hard
        case 4:        return 3   // Good
        default:       return 4   // Easy
        }
    }

    private static func initialMemory(rating: Int) -> (s: Double, d: Double) {
        let s = max(0.1, w[rating - 1])          // w[0]..w[3]
        let d = clamp(w[4] - (Double(rating) - 3) * w[5], low: 1, high: 10)
        return (s, d)
    }

    private static func nextDifficulty(d: Double, rating: Int) -> Double {
        let delta = -w[6] * (Double(rating) - 3)
        return clamp(d + delta * ((10 - d) / 9), low: 1, high: 10)
    }

    private static func nextStabilityAfterRecall(d: Double, s: Double, r: Double, rating: Int) -> Double {
        let bonus: Double = rating == 4 ? w[15] : 0
        let value = s * (
            exp(w[8]) *
            (11 - d) *
            pow(s, -w[9]) *
            (exp((1 - r) * w[10]) - 1) *
            (1 + bonus)
        )
        return max(0.01, value)
    }

    private static func nextStabilityAfterForgetting(d: Double, s: Double, r: Double) -> Double {
        let value = w[11] *
            pow(d, -w[12]) *
            (pow(s + 1, w[13]) - 1) *
            exp((1 - r) * w[14])
        return max(0.01, value)
    }

    private static func nextInterval(stability: Double) -> Int {
        let interval = (9 * stability * (1 / requestRetention - 1)).rounded()
        return min(maximumInterval, max(1, Int(interval)))
    }

    private static func daysBetween(_ from: Date, _ to: Date) -> Double {
        max(0, to.timeIntervalSince(from) / 86400)
    }

    private static func clamp(_ v: Double, low: Double, high: Double) -> Double {
        min(high, max(low, v))
    }
}
