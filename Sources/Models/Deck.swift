import Foundation
import SwiftData

@Model
final class Deck {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Card.deck) var cards: [Card]

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
