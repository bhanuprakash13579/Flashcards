import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// JSON shape for export/import. Stable — versioned for forward compatibility.
struct BackupFile: Codable {
    let version: Int
    let exportedAt: Date
    let decks: [DeckDTO]
    let tags: [TagDTO]?

    struct TagDTO: Codable {
        let id: UUID
        let name: String
        let colorHex: String
        let createdAt: Date
        let deckIDs: [UUID]
    }

    struct DeckDTO: Codable {
        let id: UUID
        let name: String
        let colorHex: String
        let createdAt: Date
        let cards: [CardDTO]
        let isPinned: Bool?
        let sortOrder: Int?
        let isDeleted: Bool?
        let deletedAt: Date?
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
        let option1: String?
        let option2: String?
        let option3: String?
        let storedExplanation: String?
        let userDifficulty: Int?
        let fsrsStability: Double?
        let fsrsDifficulty: Double?
        let ratingHistory: String?
        // Chapter / timing fields (optional for backward compat with old backups)
        let chapter: String?
        let chapterName: String?
        let questionType: String?
        let timeLimitSeconds: Int?
    }
}

enum BackupService {
    static let currentVersion = 2

    /// Build a BackupFile from current SwiftData state.
    static func snapshot(context: ModelContext) throws -> BackupFile {
        let decks = try context.fetch(FetchDescriptor<Deck>())
        let tags  = try context.fetch(FetchDescriptor<Tag>())

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
                        backImageBase64: c.backImageData?.base64EncodedString(),
                        option1: c.option1,
                        option2: c.option2,
                        option3: c.option3,
                        storedExplanation: c.storedExplanation,
                        userDifficulty: c.userDifficulty,
                        fsrsStability: c.fsrsStability,
                        fsrsDifficulty: c.fsrsDifficulty,
                        ratingHistory: c.ratingHistory.isEmpty ? nil : c.ratingHistory,
                        chapter: c.chapter.isEmpty ? nil : c.chapter,
                        chapterName: c.chapterName.isEmpty ? nil : c.chapterName,
                        questionType: c.questionType,
                        timeLimitSeconds: c.timeLimitSeconds
                    )
                },
                isPinned: d.isPinned,
                sortOrder: d.sortOrder,
                isDeleted: d.isDeleted,
                deletedAt: d.deletedAt
            )
        }
        let dtoTags = tags.map { t in
            BackupFile.TagDTO(
                id: t.id,
                name: t.name,
                colorHex: t.colorHex,
                createdAt: t.createdAt,
                deckIDs: t.decks.map(\.id)
            )
        }
        return BackupFile(version: currentVersion, exportedAt: Date(), decks: dtoDecks, tags: dtoTags)
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

    /// Load + decode a backup file. Safe to call from any thread.
    static func loadBackupFile(from url: URL) throws -> BackupFile {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    /// Apply an already-decoded backup to a SwiftData context. Must run on the main actor.
    @discardableResult
    static func applyBackup(_ backup: BackupFile, into context: ModelContext, mode: MergeMode) throws -> (decks: Int, cards: Int) {
        if mode == .replaceAll {
            try wipe(context: context)
        }

        var existingDecks: [UUID: Deck] = [:]
        var existingCards: [UUID: Card] = [:]
        var existingTags:  [UUID: Tag]  = [:]

        if mode == .mergeUpsert {
            for d in try context.fetch(FetchDescriptor<Deck>()) { existingDecks[d.id] = d }
            for c in try context.fetch(FetchDescriptor<Card>()) { existingCards[c.id] = c }
            for t in try context.fetch(FetchDescriptor<Tag>())  { existingTags[t.id] = t }
        }

        var deckCount = 0
        var cardCount = 0

        // Restore decks + cards
        var restoredDecks: [UUID: Deck] = [:]
        for dDTO in backup.decks {
            let deck: Deck
            if let existing = existingDecks[dDTO.id] {
                existing.name = dDTO.name
                existing.colorHex = dDTO.colorHex
                existing.isPinned = dDTO.isPinned ?? existing.isPinned
                existing.sortOrder = dDTO.sortOrder ?? existing.sortOrder
                existing.isDeleted = dDTO.isDeleted ?? existing.isDeleted
                existing.deletedAt = dDTO.deletedAt ?? existing.deletedAt
                deck = existing
            } else {
                deck = Deck(name: dDTO.name, colorHex: dDTO.colorHex)
                deck.id = dDTO.id
                deck.createdAt = dDTO.createdAt
                deck.isPinned = dDTO.isPinned ?? false
                deck.sortOrder = dDTO.sortOrder ?? 0
                deck.isDeleted = dDTO.isDeleted ?? false
                deck.deletedAt = dDTO.deletedAt
                context.insert(deck)
            }
            restoredDecks[deck.id] = deck
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
                    existing.option1 = cDTO.option1 ?? existing.option1
                    existing.option2 = cDTO.option2 ?? existing.option2
                    existing.option3 = cDTO.option3 ?? existing.option3
                    existing.storedExplanation = cDTO.storedExplanation ?? existing.storedExplanation
                    existing.userDifficulty = cDTO.userDifficulty ?? existing.userDifficulty
                    existing.fsrsStability  = cDTO.fsrsStability  ?? existing.fsrsStability
                    existing.fsrsDifficulty = cDTO.fsrsDifficulty ?? existing.fsrsDifficulty
                    if let h = cDTO.ratingHistory { existing.ratingHistory = h }
                    if let ch = cDTO.chapter,    !ch.isEmpty  { existing.chapter    = ch }
                    if let cn = cDTO.chapterName, !cn.isEmpty { existing.chapterName = cn }
                    if let qt = cDTO.questionType             { existing.questionType = qt }
                    if let tl = cDTO.timeLimitSeconds         { existing.timeLimitSeconds = tl }
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
                    card.option1 = cDTO.option1
                    card.option2 = cDTO.option2
                    card.option3 = cDTO.option3
                    card.storedExplanation = cDTO.storedExplanation
                    card.userDifficulty = cDTO.userDifficulty ?? 0
                    card.fsrsStability  = cDTO.fsrsStability
                    card.fsrsDifficulty = cDTO.fsrsDifficulty
                    card.ratingHistory  = cDTO.ratingHistory ?? ""
                    card.chapter         = cDTO.chapter ?? ""
                    card.chapterName     = cDTO.chapterName ?? ""
                    card.questionType    = cDTO.questionType ?? "factual"
                    card.timeLimitSeconds = cDTO.timeLimitSeconds ?? 0
                    context.insert(card)
                }
                cardCount += 1
            }
        }

        // Restore tags
        for tDTO in backup.tags ?? [] {
            let tag: Tag
            if let existing = existingTags[tDTO.id] {
                existing.name = tDTO.name
                existing.colorHex = tDTO.colorHex
                tag = existing
            } else {
                tag = Tag(name: tDTO.name, colorHex: tDTO.colorHex)
                tag.id = tDTO.id
                tag.createdAt = tDTO.createdAt
                context.insert(tag)
            }
            tag.decks = tDTO.deckIDs.compactMap { restoredDecks[$0] }
        }

        try context.save()
        return (deckCount, cardCount)
    }

    @discardableResult
    static func restore(from url: URL, into context: ModelContext, mode: MergeMode) throws -> (decks: Int, cards: Int) {
        let backup = try loadBackupFile(from: url)
        return try applyBackup(backup, into: context, mode: mode)
    }

    private static func wipe(context: ModelContext) throws {
        for d in try context.fetch(FetchDescriptor<Deck>()) { context.delete(d) }
        for c in try context.fetch(FetchDescriptor<Card>()) { context.delete(c) }
        for t in try context.fetch(FetchDescriptor<Tag>())  { context.delete(t) }
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
