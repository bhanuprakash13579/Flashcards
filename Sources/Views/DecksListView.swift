import SwiftUI
import SwiftData

struct DecksListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @State private var showingNewDeck = false
    @State private var showingSettings = false
    @State private var newDeckName = ""
    @State private var search = ""

    private var filtered: [Deck] {
        guard !search.isEmpty else { return decks }
        let q = search.lowercased()
        return decks.filter { $0.name.lowercased().contains(q) }
    }

    private var totalDue: Int { decks.reduce(0) { $0 + $1.dueCount } }

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    EmptyDecksHint { showingNewDeck = true }
                } else {
                    List {
                        streakHeader
                        ForEach(filtered) { deck in
                            NavigationLink(value: deck) {
                                DeckRow(deck: deck)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Decks")
            .searchable(text: $search, prompt: "Search decks")
            .navigationDestination(for: Deck.self) { DeckDetailView(deck: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNewDeck = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNewDeck) { newDeckSheet }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private var streakHeader: some View {
        Section {
            HStack(spacing: 0) {
                streakCell(
                    value: StudyHistory.currentStreak,
                    label: StudyHistory.currentStreak == 1 ? "day streak" : "day streak",
                    icon: "flame.fill",
                    tint: Theme.streak
                )
                Divider().frame(height: 36).padding(.horizontal, Theme.Space.s)
                streakCell(
                    value: StudyHistory.todayReviews(),
                    label: "reviewed today",
                    icon: "checkmark.circle.fill",
                    tint: Theme.success
                )
                Divider().frame(height: 36).padding(.horizontal, Theme.Space.s)
                streakCell(
                    value: totalDue,
                    label: "due now",
                    icon: "clock.fill",
                    tint: Theme.focus
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.xs)
        }
    }

    private func streakCell(value: Int, label: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint).font(.caption)
                Text("\(value)").font(.title3).fontWeight(.bold)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var newDeckSheet: some View {
        NavigationStack {
            Form {
                TextField("Deck name", text: $newDeckName)
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { reset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(newDeckName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(180)])
    }

    private func create() {
        let trimmed = newDeckName.trimmingCharacters(in: .whitespaces)
        let deck = Deck(name: trimmed, colorHex: DeckPalette.random())
        ctx.insert(deck)
        reset()
    }

    private func reset() {
        newDeckName = ""
        showingNewDeck = false
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets { ctx.delete(filtered[i]) }
    }
}

private struct DeckRow: View {
    let deck: Deck
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: deck.colorHex))
                .frame(width: 6, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.name).font(.body).fontWeight(.medium)
                Text("\(deck.cards.count) cards · \(deck.dueCount) due")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if deck.dueCount > 0 {
                Text("\(deck.dueCount)")
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EmptyDecksHint: View {
    let onCreate: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No decks yet").font(.title3).fontWeight(.semibold)
            Text("Tap + to create your first deck.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Create deck", action: onCreate)
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .padding()
    }
}
