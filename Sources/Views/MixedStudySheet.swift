import SwiftUI
import SwiftData

/// Cross-deck interleaved flashcard session — pulls due cards from all (or selected) decks
/// and shuffles them together for the "desirable difficulty" interleaving effect.
struct MixedStudySheet: View {
    let allDecks: [Deck]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIds: Set<UUID> = []
    @State private var started = false

    private var activeDecks: [Deck] {
        selectedIds.isEmpty ? allDecks : allDecks.filter { selectedIds.contains($0.id) }
    }

    private var dueCards: [Card] {
        activeDecks.flatMap { deck in
            deck.cards.filter { $0.nextReview <= Date() || $0.isNew }
        }.shuffled()
    }

    private var firstDeck: Deck? { activeDecks.first ?? allDecks.first }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                deckSelectionSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mix & Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { startButton }
            }
            .navigationDestination(isPresented: $started) {
                if let deck = firstDeck {
                    StudyView(deck: deck, cards: dueCards.isEmpty ? nil : dueCards)
                }
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(dueCards.count) cards due")
                        .font(.headline)
                    Text("From \(activeDecks.count) deck\(activeDecks.count == 1 ? "" : "s") · shuffled together")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Interleaving topics during one session improves exam performance by up to 25% compared to studying one deck at a time (Kornell & Bjork, 2008).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var deckSelectionSection: some View {
        Section {
            Button {
                if selectedIds.isEmpty { selectedIds = Set(allDecks.map(\.id)) }
                else { selectedIds.removeAll() }
            } label: {
                let allOn = selectedIds.isEmpty
                Label(allOn ? "Custom selection" : "Use all decks",
                      systemImage: allOn ? "slider.horizontal.3" : "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }

            if !selectedIds.isEmpty {
                ForEach(allDecks) { deck in
                    Button {
                        if selectedIds.contains(deck.id) { selectedIds.remove(deck.id) }
                        else { selectedIds.insert(deck.id) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selectedIds.contains(deck.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedIds.contains(deck.id) ? Color(hex: deck.colorHex) : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.name).foregroundStyle(.primary)
                                Text("\(deck.dueCount) due · \(deck.cards.count) total")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: { Text("Decks") }
    }

    private var startButton: some View {
        Button {
            guard !dueCards.isEmpty else { return }
            started = true
        } label: {
            Text("Start")
                .fontWeight(.semibold)
        }
        .disabled(dueCards.isEmpty)
    }
}
