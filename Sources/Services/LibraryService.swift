import Foundation
import SwiftData

// MARK: - Manifest models (mirrors library_manifest.json)

struct LibraryManifest: Codable {
    let subjects: [LibrarySubject]

    // The top-level manifest JSON is an array, so decode from [LibrarySubject].
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [LibrarySubject] = []
        while !container.isAtEnd {
            items.append(try container.decode(LibrarySubject.self))
        }
        subjects = items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        for s in subjects { try container.encode(s) }
    }
}

struct LibrarySubject: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let cardCount: Int
    let filename: String
    let chapters: [LibraryChapter]
}

struct LibraryChapter: Codable, Identifiable {
    let name: String
    let cardCount: Int
    let deckId: String   // matches the deck id inside the subject JSON

    var id: String { deckId }
}

// MARK: - Service

enum LibraryService {

    // MARK: Load manifest from app bundle

    static func loadManifest() -> [LibrarySubject] {
        guard let url = Bundle.main.url(forResource: "library_manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data)
        else { return [] }
        return manifest.subjects
    }

    // MARK: Import selected chapters from a subject into SwiftData

    /// Imports the chapters whose deckIds are in `selectedDeckIds` from the named subject file.
    /// Creates new Deck(s) in the context. Does NOT touch any existing user data.
    @discardableResult
    @MainActor
    static func importChapters(
        subjectFilename: String,
        selectedDeckIds: Set<String>,
        parentSubjectName: String,
        into context: ModelContext
    ) throws -> (decks: Int, cards: Int) {
        guard let url = Bundle.main.url(
            forResource: subjectFilename.replacingOccurrences(of: ".json", with: ""),
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url) else {
            throw LibraryError.fileNotFound(subjectFilename)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(BackupFile.self, from: data)

        var deckCount = 0
        var cardCount = 0

        // Normalize to uppercase so lowercase manifest IDs match Swift's UUID.uuidString
        let normalizedIds = Set(selectedDeckIds.map { $0.uppercased() })

        // Build lookup maps for existing decks and cards to enable merge (not just skip)
        let existingDecks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        let existingDeckMap = Dictionary(uniqueKeysWithValues: existingDecks.map { ($0.id, $0) })
        let existingCardIds = Set(existingDecks.flatMap { $0.cards.map(\.id) })

        for dDTO in backup.decks {
            guard normalizedIds.contains(dDTO.id.uuidString) else { continue }

            // Reuse existing deck or create new one
            let deck: Deck
            if let existing = existingDeckMap[dDTO.id] {
                deck = existing
            } else {
                let newDeck = Deck(name: "\(parentSubjectName) — \(dDTO.name)", colorHex: dDTO.colorHex)
                newDeck.id        = dDTO.id
                newDeck.createdAt = dDTO.createdAt
                newDeck.sortOrder = dDTO.sortOrder ?? 0
                context.insert(newDeck)
                deckCount += 1
                deck = newDeck
            }

            // Add only cards that don't already exist (merge new cards into existing deck)
            for cDTO in dDTO.cards {
                guard !existingCardIds.contains(cDTO.id) else { continue }
                let card = Card(front: cDTO.front, back: cDTO.back, deck: deck)
                card.id               = cDTO.id
                card.box              = cDTO.box
                card.nextReview       = cDTO.nextReview
                card.createdAt        = cDTO.createdAt
                card.ease             = cDTO.ease ?? 2.5
                card.option1          = cDTO.option1
                card.option2          = cDTO.option2
                card.option3          = cDTO.option3
                card.storedExplanation = cDTO.storedExplanation
                card.chapter          = cDTO.chapter ?? ""
                card.chapterName      = cDTO.chapterName ?? dDTO.name
                card.questionType     = cDTO.questionType ?? "factual"
                card.timeLimitSeconds = cDTO.timeLimitSeconds ?? 0
                context.insert(card)
                cardCount += 1
            }
        }

        try context.save()
        return (deckCount, cardCount)
    }

    // MARK: Auto-classify chapter for user-created / user-imported cards

    /// Infers chapter name from deck name and card back text (for cards that have no chapter set).
    /// Called once during import of non-library JSON files.
    static func autoClassify(card: Card, deckName: String) {
        guard card.chapter.isEmpty else { return }

        // Try to extract EPFO-style code from back text: "II.4 Applicability — ..."
        let backText = card.back
        let pattern  = #"\b([IVXLC]+\.[0-9A-Za-z]+)\s+([A-Za-z][^\n—\-–]{3,40}?)(?:\s*[—\-–]|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: backText, range: NSRange(backText.startIndex..., in: backText)),
           let codeRange    = Range(match.range(at: 1), in: backText),
           let nameRange    = Range(match.range(at: 2), in: backText) {
            card.chapter     = String(backText[codeRange])
            card.chapterName = String(backText[nameRange]).trimmingCharacters(in: .whitespaces)
        }

        // Auto question-type from deck name (fast heuristic, no user input needed)
        let dn = deckName.lowercased()
        if dn.contains("quant") || dn.contains("math") || dn.contains("numeric") {
            card.questionType    = "arithmetic"
            card.timeLimitSeconds = 45
        } else if dn.contains("reason") || dn.contains("logic") {
            card.questionType    = "reasoning"
            card.timeLimitSeconds = 38
        } else if dn.contains("english") || dn.contains("vocab") || dn.contains("grammar") {
            card.questionType    = "verbal"
            card.timeLimitSeconds = 25
        } else if dn.contains("science") || dn.contains("physics") || dn.contains("chemistry") || dn.contains("biology") {
            card.questionType    = "science"
            card.timeLimitSeconds = 28
        } else if dn.contains("epf") || dn.contains("eps") || dn.contains("edli") || dn.contains("labour") || dn.contains("polity") {
            card.questionType    = "legal"
            card.timeLimitSeconds = 25
        } else if dn.contains("account") {
            card.questionType    = "accounting"
            card.timeLimitSeconds = 32
        } else {
            card.questionType    = "factual"
            card.timeLimitSeconds = 28
        }
    }

    enum LibraryError: Error, LocalizedError {
        case fileNotFound(String)
        var errorDescription: String? {
            if case .fileNotFound(let f) = self { return "Library file not found: \(f)" }
            return nil
        }
    }
}
