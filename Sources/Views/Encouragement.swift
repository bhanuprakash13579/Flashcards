import Foundation

/// Variable reinforcement copy. Identical praise every time fades fast — varied micro-copy
/// keeps end-of-session moments meaningful without becoming patronising.
enum Encouragement {

    /// End-of-session — neutral but warm.
    static let sessionDone: [String] = [
        "Locked in.",
        "That's a few more in long-term memory.",
        "Quiet streak of effort. Worth it.",
        "Reps banked.",
        "Good run — see you tomorrow.",
        "Steady wins.",
        "Tiny, regular — that's how it sticks.",
        "Done. Brain rewiring."
    ]

    /// Streak hit a notable number.
    static let streakMilestone: [String] = [
        "You showed up again.",
        "Consistency is doing its job.",
        "The chain holds.",
        "Quiet daily wins compound."
    ]

    /// Got a struggling card right after several wrongs.
    static let recoveredHard: [String] = [
        "There it is.",
        "Stuck the landing.",
        "Earned that one.",
        "Worth the reps."
    ]

    /// Daily-goal hit.
    static let dailyGoalHit: [String] = [
        "Today's goal: done.",
        "Daily reps in the bank.",
        "On track. Keep light tomorrow."
    ]

    /// A gentle prompt only when streak ≥ 3 and no review yet today (loss aversion).
    static let streakAtRisk: [String] = [
        "A few minutes today keeps the streak.",
        "One short round protects what you've built.",
        "Don't let today break the chain."
    ]

    static func random(_ pool: [String]) -> String {
        pool.randomElement() ?? ""
    }
}
