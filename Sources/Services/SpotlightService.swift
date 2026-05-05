import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes decks in Spotlight so they appear in iOS Search and can be opened via a tap.
enum SpotlightService {

    static let domainIdentifier = "com.bhanu.flashcards.decks"

    /// Index (or re-index) all non-deleted decks into Spotlight.
    static func indexDecks(_ decks: [Deck]) {
        let items: [CSSearchableItem] = decks.compactMap { deck in
            guard !deck.isDeleted else { return nil }
            let attr = CSSearchableItemAttributeSet(contentType: .item)
            attr.title = deck.name
            attr.contentDescription = "\(deck.cards.count) cards · \(deck.dueCount) due"
            attr.keywords = ["flashcard", "deck", "study", "review", deck.name]
            return CSSearchableItem(
                uniqueIdentifier: deck.id.uuidString,
                domainIdentifier: domainIdentifier,
                attributeSet: attr
            )
        }
        CSSearchableIndex.default().indexSearchableItems(items, completionHandler: nil)
    }

    /// Remove all indexed decks (e.g., on data wipe).
    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier], completionHandler: nil)
    }

    /// Remove a single deck from the index.
    static func remove(deckID: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [deckID.uuidString], completionHandler: nil)
    }

    // MARK: - Siri Shortcut donation

    /// Donate a "Start Review" shortcut for the given deck so Siri learns the user's habits.
    static func donateReviewShortcut(for deck: Deck) {
        let activity = NSUserActivity(activityType: "com.bhanu.flashcards.review")
        activity.title = "Review \(deck.name)"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier("review-\(deck.id.uuidString)")
        activity.userInfo = ["deckID": deck.id.uuidString]
        activity.becomeCurrent()
    }
}
