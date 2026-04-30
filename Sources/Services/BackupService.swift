import Foundation
import SwiftData
import UniformTypeIdentifiers

/// JSON shape for export/import. Stable — versioned for forward compatibility.
struct BackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let decks: [DeckDTO]

    struct DeckDTO: Codable {
        let id: UUID
        let name: String
        let colorHex: String
        let createdAt: Date
        let cards: [CardDTO]
    }

    struct CardDTO: Codable {
        let id: UUID
        let front: String
        let back: String
        let box: Int
        let nextReview: Date
        let lastReviewed: Date?
        let createdAt: Date
        let correctCount: Int?
        let wrongCount: Int?
        let ease: Double?
        let interval: Int?
        let repetitions: Int?
        let frontImageBase64: String?
        let backImageBase64: String?
    }
}

enum BackupService {
    static let currentVersion = 1

    /// Build a BackupFile from current SwiftData state.
    static func snapshot(context: ModelContext) throws -> BackupFile {
        let descriptor = FetchDescriptor<Deck>()
        let decks = try context.fetch(descriptor)
        let dtoDecks = decks.map { d in
            BackupFile.DeckDTO(
                id: d.id,
                name: d.name,
                colorHex: d.colorHex,
                createdAt: d.createdAt,
                cards: d.cards.map { c in
                    BackupFile.CardDTO(
                        id: c.id,
                        front: c.front,
                        back: c.back,
                        box: c.box,
                        nextReview: c.nextReview,
                        lastReviewed: c.lastReviewed,
                        createdAt: c.createdAt,
                        correctCount: c.correctCount,
                        wrongCount: c.wrongCount,
                        ease: c.ease,
                        interval: c.interval,
                        repetitions: c.repetitions,
                        frontImageBase64: c.frontImageData?.base64EncodedString(),
                        backImageBase64: c.backImageData?.base64EncodedString()
                    )
                }
            )
        }
        return BackupFile(version: currentVersion, exportedAt: Date(), decks: dtoDecks)
    }

    /// Encode a snapshot to pretty-printed JSON.
    static func encode(_ backup: BackupFile) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(backup)
    }

    /// Decode JSON data into a BackupFile.
    static func decode(_ data: Data) throws -> BackupFile {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(BackupFile.self, from: data)
    }

    /// Write a fresh backup to a temporary file and return its URL — for `.fileExporter`.
    static func writeTempBackup(context: ModelContext) throws -> URL {
        let backup = try snapshot(context: context)
        let data = try encode(backup)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flashcards-backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Strategy for restore.
    enum MergeMode {
        case replaceAll      // wipe existing data, then import
        case mergeUpsert     // upsert by id; existing cards updated, new ones added
    }

    @discardableResult
    static func restore(from url: URL, into context: ModelContext, mode: MergeMode) throws -> (decks: Int, cards: Int) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let backup = try decode(data)

        if mode == .replaceAll {
            try wipe(context: context)
        }

        var existingDecks: [UUID: Deck] = [:]
        var existingCards: [UUID: Card] = [:]
        if mode == .mergeUpsert {
            let allDecks = try context.fetch(FetchDescriptor<Deck>())
            for d in allDecks { existingDecks[d.id] = d }
            let allCards = try context.fetch(FetchDescriptor<Card>())
            for c in allCards { existingCards[c.id] = c }
        }

        var deckCount = 0
        var cardCount = 0
        for dDTO in backup.decks {
            let deck: Deck
            if let existing = existingDecks[dDTO.id] {
                existing.name = dDTO.name
                existing.colorHex = dDTO.colorHex
                deck = existing
            } else {
                deck = Deck(name: dDTO.name, colorHex: dDTO.colorHex)
                deck.id = dDTO.id
                deck.createdAt = dDTO.createdAt
                context.insert(deck)
            }
            deckCount += 1

            for cDTO in dDTO.cards {
                let frontImg = cDTO.frontImageBase64.flatMap { Data(base64Encoded: $0) }
                let backImg  = cDTO.backImageBase64.flatMap  { Data(base64Encoded: $0) }

                if let existing = existingCards[cDTO.id] {
                    existing.front = cDTO.front
                    existing.back = cDTO.back
                    existing.box = cDTO.box
                    existing.nextReview = cDTO.nextReview
                    existing.lastReviewed = cDTO.lastReviewed
                    existing.correctCount = cDTO.correctCount ?? existing.correctCount
                    existing.wrongCount = cDTO.wrongCount ?? existing.wrongCount
                    existing.ease = cDTO.ease ?? existing.ease
                    existing.interval = cDTO.interval ?? existing.interval
                    existing.repetitions = cDTO.repetitions ?? existing.repetitions
                    if let frontImg { existing.frontImageData = frontImg }
                    if let backImg  { existing.backImageData = backImg }
                    existing.deck = deck
                } else {
                    let card = Card(front: cDTO.front, back: cDTO.back, deck: deck)
                    card.id = cDTO.id
                    card.box = cDTO.box
                    card.nextReview = cDTO.nextReview
                    card.lastReviewed = cDTO.lastReviewed
                    card.createdAt = cDTO.createdAt
                    card.correctCount = cDTO.correctCount ?? 0
                    card.wrongCount = cDTO.wrongCount ?? 0
                    card.ease = cDTO.ease ?? 2.5
                    card.interval = cDTO.interval ?? 0
                    card.repetitions = cDTO.repetitions ?? 0
                    card.frontImageData = frontImg
                    card.backImageData = backImg
                    context.insert(card)
                }
                cardCount += 1
            }
        }
        try context.save()
        return (deckCount, cardCount)
    }

    private static func wipe(context: ModelContext) throws {
        let decks = try context.fetch(FetchDescriptor<Deck>())
        for d in decks { context.delete(d) }
        let cards = try context.fetch(FetchDescriptor<Card>())
        for c in cards { context.delete(c) }
        try context.save()
    }
}

/// FileDocument wrapper so SwiftUI's `.fileExporter` can save the JSON.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
