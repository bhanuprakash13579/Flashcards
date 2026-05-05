import Foundation
import SwiftData

@Model
final class Card {
    var id: UUID  // unique by UUID generation; @Attribute(.unique) omitted for CloudKit compat
    var front: String
    var back: String

    // Scheduling fields shared by both SM-2 (legacy) and FSRS.
    // `box` retained for display. `ease` kept for SM-2 cards imported before FSRS.
    var box: Int
    var ease: Double = 2.5
    var interval: Int = 0          // days
    var repetitions: Int = 0

    // FSRS memory model (nil = card not yet reviewed under FSRS)
    var fsrsStability: Double? = nil    // S: days until 90% retention
    var fsrsDifficulty: Double? = nil   // D: 1 (easy) – 10 (hard)
    var ratingHistory: String = ""      // compact string of last 20 ratings, e.g. "4,2,4,4"

    var nextReview: Date
    var lastReviewed: Date?
    var createdAt: Date
    var correctCount: Int = 0
    var wrongCount: Int = 0

    @Attribute(.externalStorage) var frontImageData: Data?
    @Attribute(.externalStorage) var backImageData: Data?

    // Optional wrong-answer distractors for MCQ mode (correct answer is always `back`).
    var option1: String?
    var option2: String?
    var option3: String?
    
    // Explicit explanation field. If nil, the app falls back to extracting it from the back text.
    var storedExplanation: String?
    
    // User-assigned difficulty (0 = unclassified, 1 = easy, 2 = medium, 3 = hard)
    var userDifficulty: Int = 0

    // Chapter classification — auto-populated on import from JSON
    // chapter: machine code e.g. "Fundamental Rights" / "II.4"
    // chapterName: human label identical to chapter for library cards, topic name for EPFO
    var chapter: String = ""
    var chapterName: String = ""

    // Question type drives the per-card timer in timed practice.
    // Values: "arithmetic" | "reasoning" | "verbal" | "legal" | "science" | "factual" | "accounting"
    var questionType: String = "factual"
    // Per-question time budget in seconds (0 = untimed)
    var timeLimitSeconds: Int = 0

    var deck: Deck?

    init(front: String, back: String, deck: Deck? = nil) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.box = 1
        self.ease = 2.5
        self.interval = 0
        self.repetitions = 0
        self.nextReview = Date()
        self.createdAt = Date()
        self.correctCount = 0
        self.wrongCount = 0
        self.ratingHistory = ""
        self.deck = deck
    }

    /// The clean correct answer for MCQ mode, stripping out leading (A) / B. and trailing explanations.
    var cleanMCQAnswer: String {
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
        var main = b.components(separatedBy: "\n\n").first ?? b

        if let markerIndex = main.firstIndex(of: "■") {
            main = String(main[..<markerIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Only strip explicit option markers — "(A) text", "[B] text", "A. text", "B) text"
        // Requires bracket OR letter+punctuation so words like "Article", "Budget" are untouched.
        let pattern = #"^\s*(\([a-zA-Z]\)|\[[a-zA-Z]\])\.?\s*|^\s*[a-zA-Z][.):-]\s+"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: main, range: NSRange(main.startIndex..., in: main)),
           let range = Range(match.range, in: main) {
            let s = String(main[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? main : s
        }
        return main
    }
    
    /// Returns the explanation text (either explicitly stored, or extracted from the back string).
    var explanation: String? {
        var expl: String? = nil
        
        if let explicit = storedExplanation?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            expl = explicit
        } else {
            let parts = back.components(separatedBy: "\n\n")
            if parts.count > 1 {
                expl = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        guard var text = expl, !text.isEmpty else { return nil }
        
        // Strip overhead prefix like "II.4 Applicability — " or "XVI.63 Art & Culture - "
        let pattern = "^[IVXLCDM]+\\.\\d+[^—\\-]+[—\\-]\\s*"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            text = String(text[range.upperBound...])
        }
        
        // Strip trailing overhead
        text = text.replacingOccurrences(of: "# Ans Explanation", with: "")
                   .trimmingCharacters(in: .whitespacesAndNewlines)
                   
        return text.isEmpty ? nil : text
    }

    /// All MCQ choices: correct answer + stored wrong options (if any).
    var storedMCQOptions: [String]? {
        let wrongs = [option1, option2, option3].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !wrongs.isEmpty else { return nil }
        return ([cleanMCQAnswer] + wrongs).shuffled()
    }

    /// `true` if the card has been answered wrong noticeably more often than right.
    var isStruggling: Bool { wrongCount > correctCount && wrongCount >= 2 }

    /// `true` if the user has never successfully answered the card. Used for the daily new-card cap.
    var isNew: Bool { repetitions == 0 }

    /// Last N ratings as an array, newest last. Decoded from `ratingHistory`.
    var recentRatings: [Int] {
        ratingHistory.split(separator: ",").compactMap { Int($0) }
    }

    /// Apply a grade (quality 0-5). Uses FSRS when available, SM-2 for legacy compat.
    /// In the 2-button UI: wrong=2, right=4, easy=5.
    func rate(_ quality: Int) {
        FSRS.apply(rating: quality, to: self)
        if quality >= 3 { correctCount += 1 } else { wrongCount += 1 }
        // Record in history (keep last 20)
        var ratings = recentRatings
        ratings.append(quality)
        if ratings.count > 20 { ratings = Array(ratings.suffix(20)) }
        ratingHistory = ratings.map(String.init).joined(separator: ",")
        // Mirror onto Leitner box for stats display
        box = max(1, min(5, repetitions == 0 ? 1 : min(repetitions + 1, 5)))
    }

    func markCorrect() { rate(4) }
    func markWrong()   { rate(2) }
}
