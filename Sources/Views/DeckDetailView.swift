import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var ctx

    @State private var showEditor = false
    @State private var editingCard: Card?
    @State private var search = ""
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showPractice = false
    @State private var showBulkImport = false
    @State private var showStats = false

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
                Menu {
                    Button { showEditor = true } label: {
                        Label("Add card", systemImage: "plus")
                    }
                    Button { showBulkImport = true } label: {
                        Label("Bulk import…", systemImage: "square.and.arrow.down.on.square")
                    }
                    Button { showStats = true } label: {
                        Label("Stats", systemImage: "chart.bar")
                    }
                    Divider()
                    Button {
                        renameText = deck.name
                        showRename = true
                    } label: {
                        Label("Rename deck", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
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
        .alert("Rename deck", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { deck.name = t }
            }
        }
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
                Button { editingCard = card } label: {
                    CardRow(card: card)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        ctx.delete(card)
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
                    Text("Due").font(.caption2).foregroundStyle(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
