import SwiftUI
import SwiftData

struct DecksListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(filter: #Predicate<Deck> { $0.isDeleted == false }, sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showingNewDeck = false
    @State private var editingDeck: Deck?
    @State private var showingSettings = false
    @State private var showingExam = false
    @State private var showingLibrary = false
    @State private var showingMixedStudy = false
    @State private var search = ""
    @State private var debouncedSearch = ""
    @State private var selectedTag: Tag?
    @State private var selectedDecks = Set<Deck>()
    @State private var isSelecting = false

    @AppStorage("dailyReviewGoal") private var dailyReviewGoal = 20

    private var filtered: [Deck] {
        var result = decks
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(where: { $0.id == tag.id }) }
        }
        if !debouncedSearch.isEmpty {
            let q = debouncedSearch.lowercased()
            // Global search: match deck name OR any card's front/back text
            result = result.filter { deck in
                deck.name.lowercased().contains(q) ||
                deck.cards.contains { card in
                    card.front.lowercased().contains(q) ||
                    card.back.lowercased().contains(q)
                }
            }
        }
        // Sort pinned decks to top, then by sortOrder, then by creation date (newest first)
        result.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
            return a.createdAt > b.createdAt
        }
        return result
    }

    /// Cards matching the global search query (shown when searching across cards)
    private var matchingCards: [(deck: Deck, cards: [Card])] {
        guard !debouncedSearch.isEmpty else { return [] }
        let q = debouncedSearch.lowercased()
        var results: [(deck: Deck, cards: [Card])] = []
        for deck in filtered {
            let matched = deck.cards.filter {
                $0.front.lowercased().contains(q) || $0.back.lowercased().contains(q)
            }
            if !matched.isEmpty {
                results.append((deck, Array(matched.prefix(5)))) // limit per deck for performance
            }
        }
        return results
    }

    private var totalDue: Int { decks.reduce(0) { $0 + $1.dueCount } }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty && debouncedSearch.isEmpty && selectedTag == nil {
                    EmptyDecksHint { showingNewDeck = true }
                } else {
                    List {
                        streakHeader
                        if !allTags.isEmpty {
                            tagFilterRow
                        }
                        if !debouncedSearch.isEmpty && !matchingCards.isEmpty {
                            cardSearchResults
                        }
                        ForEach(filtered) { deck in
                            HStack {
                                if isSelecting {
                                    Button {
                                        if selectedDecks.contains(deck) { selectedDecks.remove(deck) }
                                        else { selectedDecks.insert(deck) }
                                    } label: {
                                        HStack {
                                            Image(systemName: selectedDecks.contains(deck) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedDecks.contains(deck) ? Color.accentColor : .secondary)
                                                .font(.title2)
                                                .padding(.trailing, 8)
                                            DeckRow(deck: deck)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink(value: deck) {
                                        DeckRow(deck: deck)
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    editingDeck = deck
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deck.isDeleted = true
                                    deck.deletedAt = Date()
                                    try? ctx.save()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    deck.isPinned.toggle()
                                } label: {
                                    Label(deck.isPinned ? "Unpin" : "Pin",
                                          systemImage: deck.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(.orange)
                            }
                        }
                        .onMove(perform: moveDecks)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Decks")
            .searchable(text: $search, prompt: "Search decks & cards")
            .task(id: search) {
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    debouncedSearch = search
                } catch { }
            }
            .navigationDestination(for: Deck.self) { DeckDetailView(deck: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if isSelecting {
                            if !selectedDecks.isEmpty {
                                Button(role: .destructive) {
                                    for deck in selectedDecks {
                                        deck.isDeleted = true
                                        deck.deletedAt = Date()
                                    }
                                    try? ctx.save()
                                    selectedDecks.removeAll()
                                    isSelecting = false
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
                            Button("Done") {
                                isSelecting = false
                                selectedDecks.removeAll()
                            }
                        } else {
                            Menu {
                                Button { isSelecting = true } label: {
                                    Label("Select multiple", systemImage: "checkmark.circle")
                                }
                                Button { showingMixedStudy = true } label: {
                                    Label("Mix & Study", systemImage: "shuffle")
                                }
                                Button { showingExam = true } label: {
                                    Label("Exam Simulator", systemImage: "timer")
                                }
                                Button { showingLibrary = true } label: {
                                    Label("Flashcard Library", systemImage: "books.vertical")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            Button { showingNewDeck = true } label: { Image(systemName: "plus") }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewDeck) {
                DeckEditorSheet(deck: nil)
            }
            .sheet(item: $editingDeck) { deck in
                DeckEditorSheet(deck: deck)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingExam) {
                ExamSimulatorView(allDecks: decks)
            }
            .sheet(isPresented: $showingLibrary) {
                LibraryView()
            }
            .sheet(isPresented: $showingMixedStudy) {
                MixedStudySheet(allDecks: decks.filter { !$0.isDeleted })
            }
            .sheet(isPresented: Binding(
                get: { !hasSeenOnboarding },
                set: { if !$0 { hasSeenOnboarding = true } }
            )) {
                OnboardingView()
            }
        }
    }

    // MARK: - Subviews

    private var streakHeader: some View {
        Section {
            // Library discovery banner (shown only when user has 0 or few decks)
            if decks.count < 3 {
                Button {
                    showingLibrary = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "books.vertical.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Explore Flashcard Library")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("8,000+ cards across 12 subjects — add what you've studied")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            VStack(spacing: Theme.Space.s) {
                HStack(spacing: 0) {
                    // Streak cell with shield badge when at-risk
                    let streakAtRisk = StudyHistory.todayReviews() == 0 &&
                        StudyHistory.todayReviews(date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()) > 0
                    streakCellShielded(
                        value: StudyHistory.currentStreak,
                        label: StudyHistory.currentStreak == 1 ? "day streak" : "days streak",
                        icon: "flame.fill",
                        tint: Theme.streak,
                        shielded: streakAtRisk
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

                // Bedtime review button — shown when user has studied today
                let todayCards = decks.flatMap { $0.cards.filter {
                    guard let lr = $0.lastReviewed else { return false }
                    return Calendar.current.isDateInToday(lr)
                }}
                if !todayCards.isEmpty && !decks.isEmpty {
                    Button {
                        showingMixedStudy = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.stars.fill").foregroundStyle(.indigo).font(.caption)
                            Text("Consolidate today's \(todayCards.count) reviewed cards before sleep")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Daily study goal progress bar
                let todayCount = StudyHistory.todayReviews()
                let goalReached = todayCount >= dailyReviewGoal
                VStack(spacing: 3) {
                    ProgressView(value: min(Double(todayCount), Double(dailyReviewGoal)),
                                 total: Double(dailyReviewGoal))
                        .tint(goalReached ? Theme.success : Theme.focus)
                    HStack {
                        Text("\(todayCount)/\(dailyReviewGoal) daily goal")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        if goalReached {
                            Text("🎯 Goal reached!")
                                .font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(Theme.success)
                        }
                    }
                }
            }
            .padding(.vertical, Theme.Space.xs)
        }
    }

    private var tagFilterRow: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tagChip(tag: nil)
                    ForEach(allTags) { tag in
                        tagChip(tag: tag)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var cardSearchResults: some View {
        Section("Matching cards") {
            ForEach(matchingCards, id: \.deck.id) { result in
                ForEach(result.cards) { card in
                    NavigationLink(value: result.deck) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.front).font(.subheadline).fontWeight(.medium).lineLimit(1)
                            Text(card.back).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(result.deck.name)
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color(hex: result.deck.colorHex).opacity(0.2),
                                            in: Capsule())
                                .foregroundStyle(Color(hex: result.deck.colorHex))
                        }
                    }
                }
            }
        }
    }

    private func tagChip(tag: Tag?) -> some View {
        let isSelected = selectedTag?.id == tag?.id
        let color = tag.map { Color(hex: $0.colorHex) } ?? Color.secondary
        return Button {
            selectedTag = (selectedTag?.id == tag?.id) ? nil : tag
        } label: {
            HStack(spacing: 4) {
                if let tag {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(tag.name)
                } else {
                    Text("All")
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? color.opacity(0.25) : Color(.tertiarySystemFill),
                        in: Capsule())
            .foregroundStyle(isSelected ? color : .secondary)
            .overlay(Capsule().stroke(isSelected ? color : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    private func streakCellShielded(value: Int, label: String, icon: String, tint: Color, shielded: Bool) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(tint).font(.caption)
                Text("\(value)").font(.title3).fontWeight(.bold)
                if shielded {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                }
            }
            Text(shielded ? "shield active" : label)
                .font(.caption2)
                .foregroundStyle(shielded ? .blue : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
    private func moveDecks(from source: IndexSet, to destination: Int) {
        var orderedDecks = filtered
        orderedDecks.move(fromOffsets: source, toOffset: destination)
        // Update sortOrder for all items in the new order
        for (index, deck) in orderedDecks.enumerated() {
            deck.sortOrder = index
        }
        try? ctx.save()
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
                HStack(spacing: 4) {
                    if deck.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(deck.name).font(.body).fontWeight(.medium)
                }
                HStack(spacing: 6) {
                    Text("\(deck.cards.count) cards · \(deck.dueCount) due")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(deck.tags.prefix(3)) { tag in
                        Text(tag.name)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color(hex: tag.colorHex).opacity(0.2),
                                        in: Capsule())
                            .foregroundStyle(Color(hex: tag.colorHex))
                    }
                }
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
