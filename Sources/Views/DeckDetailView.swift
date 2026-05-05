import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var ctx

    @State private var showEditor = false
    @State private var editingCard: Card?
    @State private var search = ""
    @State private var showPractice = false
    @State private var showBulkImport = false
    @State private var showStats = false
    @State private var showAIGenerator = false
    @State private var selectedCards = Set<Card>()
    @State private var isSelecting = false
    @State private var showDeckEditor = false
    @State private var csvDocument: CSVDocument?
    @State private var exportingCSV = false
    @State private var shareJSON: ShareableJSON?
    @State private var showShareSheet = false
    @State private var shareError: String?

    private var filtered: [Card] {
        let cards = deck.cards.sorted { $0.createdAt > $1.createdAt }
        guard !search.isEmpty else { return cards }
        let q = search.lowercased()
        return cards.filter {
            $0.front.lowercased().contains(q) || $0.back.lowercased().contains(q)
        }
    }

    private var dueCards: [Card] {
        deck.cards.filter { $0.nextReview <= Date() }
    }

    var body: some View {
        VStack(spacing: 0) {
            studyHeader
            if deck.cards.isEmpty {
                emptyState
            } else {
                cardList
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if isSelecting {
                        if !selectedCards.isEmpty {
                            Button(role: .destructive) {
                                for card in selectedCards {
                                    ctx.delete(card)
                                }
                                try? ctx.save()
                                selectedCards.removeAll()
                                isSelecting = false
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                        Button("Done") {
                            isSelecting = false
                            selectedCards.removeAll()
                        }
                    } else {
                        Menu {
                            Button { isSelecting = true } label: {
                                Label("Select multiple", systemImage: "checkmark.circle")
                            }
                            Button { showEditor = true } label: {
                                Label("Add card", systemImage: "plus")
                            }
                            Button { showBulkImport = true } label: {
                                Label("Bulk import…", systemImage: "square.and.arrow.down.on.square")
                            }
                            Button { showAIGenerator = true } label: {
                                Label("Generate with AI…", systemImage: "sparkles")
                            }
                            Button { showStats = true } label: {
                                Label("Stats", systemImage: "chart.bar")
                            }
                            Divider()
                            Button { autoTagStruggling() } label: {
                                Label("Mark struggling as Hard", systemImage: "flag.fill")
                            }
                            .disabled(deck.cards.filter(\.isStruggling).isEmpty)
                            Button { clearAllDifficulty() } label: {
                                Label("Clear all difficulty tags", systemImage: "flag.slash")
                            }
                            .disabled(deck.cards.allSatisfy { $0.userDifficulty == 0 })
                            Divider()
                            Button { prepareCSVExport() } label: {
                                Label("Export as CSV…", systemImage: "square.and.arrow.up")
                            }
                            .disabled(deck.cards.isEmpty)
                            Button { prepareShareJSON() } label: {
                                Label("Share deck as JSON…", systemImage: "square.and.arrow.up.on.square")
                            }
                            .disabled(deck.cards.isEmpty)
                            Divider()
                            Button { showDeckEditor = true } label: {
                                Label("Edit deck", systemImage: "pencil")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            CardEditorView(deck: deck, card: nil)
        }
        .sheet(item: $editingCard) { card in
            CardEditorView(deck: deck, card: card)
        }
        .sheet(isPresented: $showPractice) {
            PracticeHub(deck: deck)
        }
        .sheet(isPresented: $showBulkImport) {
            BulkImportView(deck: deck)
        }
        .sheet(isPresented: $showStats) {
            StatsView(deck: deck)
        }
        .sheet(isPresented: $showAIGenerator) {
            AICardGeneratorView(deck: deck)
        }
        .sheet(isPresented: $showDeckEditor) {
            DeckEditorSheet(deck: deck)
        }
        .sheet(isPresented: $showShareSheet) {
            if let shareJSON {
                ShareSheet(items: [shareJSON.url])
            }
        }
        .fileExporter(
            isPresented: $exportingCSV,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "\(deck.name)-cards.csv"
        ) { _ in csvDocument = nil }
        .alert("Export failed", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } }), presenting: shareError) { _ in
            Button("OK") { shareError = nil }
        } message: { msg in Text(msg) }
        .searchable(text: $search, prompt: "Search cards")
    }

    private var studyHeader: some View {
        VStack(spacing: 10) {
            HStack {
                StatPill(label: "Total", value: "\(deck.cards.count)")
                StatPill(label: "Due", value: "\(dueCards.count)", tint: .accentColor)
                Spacer()
            }
            Button { showPractice = true } label: {
                Text(dueCards.isEmpty ? "Practice" : "Practice · \(dueCards.count) due")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .disabled(deck.cards.isEmpty)
            .opacity(deck.cards.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var cardList: some View {
        List {
            ForEach(filtered) { card in
                HStack {
                    if isSelecting {
                        Button {
                            if selectedCards.contains(card) { selectedCards.remove(card) }
                            else { selectedCards.insert(card) }
                        } label: {
                            HStack {
                                Image(systemName: selectedCards.contains(card) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCards.contains(card) ? Color.accentColor : .secondary)
                                    .font(.title2)
                                    .padding(.trailing, 8)
                                CardRow(card: card)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { editingCard = card } label: {
                            CardRow(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        ctx.delete(card)
                        try? ctx.save()
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("No cards in this deck").font(.headline)
            Button("Add your first card") { showEditor = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func prepareCSVExport() {
        csvDocument = CSVDocument(CSVExportService.csvString(for: deck))
        exportingCSV = true
    }

    private func autoTagStruggling() {
        for card in deck.cards where card.isStruggling {
            card.userDifficulty = 3
        }
        try? ctx.save()
    }

    private func clearAllDifficulty() {
        for card in deck.cards {
            card.userDifficulty = 0
        }
        try? ctx.save()
    }

    /// Build a single-deck BackupFile JSON and open iOS share sheet.
    private func prepareShareJSON() {
        do {
            let dtoCards = deck.cards.map { c in
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
                    frontImageBase64: nil,
                    backImageBase64: nil,
                    option1: c.option1,
                    option2: c.option2,
                    option3: c.option3,
                    storedExplanation: c.storedExplanation,
                    userDifficulty: c.userDifficulty,
                    fsrsStability: c.fsrsStability,
                    fsrsDifficulty: c.fsrsDifficulty,
                    ratingHistory: c.ratingHistory,
                    chapter: c.chapter,
                    chapterName: c.chapterName,
                    questionType: c.questionType,
                    timeLimitSeconds: c.timeLimitSeconds
                )
            }
            let dtoDeck = BackupFile.DeckDTO(
                id: deck.id,
                name: deck.name,
                colorHex: deck.colorHex,
                createdAt: deck.createdAt,
                cards: dtoCards,
                isPinned: deck.isPinned,
                sortOrder: deck.sortOrder,
                isDeleted: deck.isDeleted,
                deletedAt: deck.deletedAt
            )
            let backup = BackupFile(
                version: BackupService.currentVersion,
                exportedAt: Date(),
                decks: [dtoDeck],
                tags: nil
            )
            let data = try BackupService.encode(backup)
            let filename = "\(deck.name.replacingOccurrences(of: " ", with: "-"))-deck.json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            shareJSON = ShareableJSON(url: url)
            showShareSheet = true
        } catch {
            shareError = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// Wrapper for the share sheet URL
private struct ShareableJSON: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet wrapper for SwiftUI
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct StatPill: View {
    let label: String
    let value: String
    var tint: Color = .secondary
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CardRow: View {
    let card: Card
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.front)
                .font(.body).fontWeight(.medium)
                .lineLimit(2)
            Text(card.back)
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text("Box \(card.box)")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tertiary, in: Capsule())
                if card.nextReview <= Date() {
                    Text("Due").font(.caption2).foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
