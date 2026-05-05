import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID  // unique by UUID generation; @Attribute(.unique) omitted for CloudKit compat
    var name: String
    var colorHex: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Card.deck) var cards: [Card]
    var tags: [Tag] = []
    var isPinned: Bool = false
    var sortOrder: Int = 0
    var isDeleted: Bool = false
    var deletedAt: Date? = nil

    init(name: String, colorHex: String = "#4F8EF7") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
        self.cards = []
    }

    var dueCount: Int {
        let now = Date()
        return cards.filter { $0.nextReview <= now }.count
    }
}
