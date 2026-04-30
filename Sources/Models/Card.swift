import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var front: String
    var back: String

    // SM-2 fields. `box` retained for legacy display + JSON compat.
    var box: Int
    var ease: Double = 2.5
    var interval: Int = 0          // days
    var repetitions: Int = 0

    var nextReview: Date
    var lastReviewed: Date?
    var createdAt: Date
    var correctCount: Int = 0
    var wrongCount: Int = 0

    @Attribute(.externalStorage) var frontImageData: Data?
    @Attribute(.externalStorage) var backImageData: Data?

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
        self.deck = deck
    }

    /// `true` if the card has been answered wrong noticeably more often than right.
    var isStruggling: Bool { wrongCount > correctCount && wrongCount >= 2 }

    /// `true` if the user has never successfully answered the card. Used for the daily new-card cap.
    var isNew: Bool { repetitions == 0 }

    /// Apply an SM-2 grade. quality: 0 (total blackout) – 5 (perfect).
    /// In the 2-button UI we map: wrong=2, right=4, easy=5.
    func rate(_ quality: Int) {
        SpacedRepetition.apply(quality: quality, to: self)
        if quality >= 3 { correctCount += 1 } else { wrongCount += 1 }
        // Mirror onto Leitner-style box 1...5 for the existing UI / stats.
        box = max(1, min(5, repetitions == 0 ? 1 : min(repetitions + 1, 5)))
    }

    func markCorrect() { rate(4) }
    func markWrong()   { rate(2) }
}
