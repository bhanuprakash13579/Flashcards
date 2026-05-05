import SwiftUI
import SwiftData

// MARK: - Practice modes

enum PracticeMode: String, CaseIterable, Identifiable {
    case flashcards, multipleChoice, written, match
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards:     return "Flashcards"
        case .multipleChoice: return "Multiple choice"
        case .written:        return "Written review"
        case .match:          return "Match pairs"
        }
    }

    var subtitle: String {
        switch self {
        case .flashcards:     return "Tap to flip · swipe to grade"
        case .multipleChoice: return "Pick the right answer from 4 options"
        case .written:        return "Type the answer — fuzzy match"
        case .match:          return "Pair fronts with backs against the clock"
        }
    }

    var systemImage: String {
        switch self {
        case .flashcards:     return "rectangle.on.rectangle"
        case .multipleChoice: return "list.bullet.rectangle"
        case .written:        return "pencil.and.outline"
        case .match:          return "square.grid.2x2"
        }
    }
}

// MARK: - PracticeHub

struct PracticeHub: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @State private var cardFilter: PracticeQueue.CardFilter = .all

    // Chapter selection — persisted per deck
    @State private var selectedChapters: Set<String> = []
    @State private var showChapterPicker = false

    private var deckChapterKey: String { "chapters_\(deck.id)" }

    private var chapters: [String] {
        let all = deck.cards.map(\.chapter).filter { !$0.isEmpty }
        return Array(Set(all)).sorted()
    }

    private var filteredCards: [Card] {
        if selectedChapters.isEmpty { return deck.cards }
        return deck.cards.filter { selectedChapters.contains($0.chapter) }
    }

    var body: some View {
        NavigationStack {
            List {
                filterSection
                if !chapters.isEmpty { chapterSection }
                Section {
                    ForEach(PracticeMode.allCases) { mode in
                        NavigationLink(value: mode) {
                            row(mode)
                        }
                        .disabled(!isAvailable(mode))
                    }
                } header: {
                    Text("Choose a practice mode")
                } footer: {
                    let count = filteredCards.count
                    if count < 4 {
                        Text("Add at least 4 cards to unlock multiple choice and match modes.")
                    } else {
                        Text("\(count) card\(count == 1 ? "" : "s") in scope · struggling appear first.")
                    }
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
            .navigationDestination(for: PracticeMode.self) { mode in
                let cards = filteredCards
                switch mode {
                case .flashcards:
                    StudyView(deck: deck, cards: cards.isEmpty ? nil : cards, cardFilter: cardFilter)
                case .multipleChoice:
                    MultipleChoiceView(deck: deck, cards: cards.isEmpty ? nil : cards,
                                       cardFilter: cardFilter)
                case .written:
                    WrittenReviewView(deck: deck, cards: cards.isEmpty ? nil : cards,
                                     cardFilter: cardFilter)
                case .match:
                    MatchView(deck: deck, cardFilter: cardFilter)
                }
            }
            .sheet(isPresented: $showChapterPicker) {
                ChapterPickerSheet(
                    chapters: chapters,
                    chapterNames: chapterNames(),
                    selected: $selectedChapters,
                    deck: deck
                )
            }
        }
        .onAppear { loadSavedChapters() }
        .onChange(of: selectedChapters) { _, _ in saveChapters() }
    }

    // MARK: Filter section

    private var filterSection: some View {
        Section {
            Picker("Card filter", selection: $cardFilter) {
                ForEach(PracticeQueue.CardFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            filterSummary
        } header: { Text("Filter") }
    }

    @ViewBuilder
    private var filterSummary: some View {
        let base = filteredCards
        let count: Int = {
            switch cardFilter {
            case .all:              return base.count
            case .dueOnly:          return base.filter { $0.nextReview <= Date() }.count
            case .struggling:       return base.filter(\.isStruggling).count
            case .newOnly:          return base.filter(\.isNew).count
            case .easyOnly:         return base.filter { $0.userDifficulty == 1 }.count
            case .mediumOnly:       return base.filter { $0.userDifficulty == 2 }.count
            case .hardOnly:         return base.filter { $0.userDifficulty == 3 }.count
            case .unclassifiedOnly: return base.filter { $0.userDifficulty == 0 }.count
            }
        }()
        Text("\(count) card\(count == 1 ? "" : "s") match this filter")
            .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Chapter section

    private var chapterSection: some View {
        Section {
            Button {
                showChapterPicker = true
            } label: {
                HStack {
                    Label("Chapter filter", systemImage: "books.vertical")
                    Spacer()
                    if selectedChapters.isEmpty {
                        Text("All chapters")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("\(selectedChapters.count) of \(chapters.count) selected")
                            .font(.subheadline).foregroundStyle(.tint)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        } header: { Text("Topics") }
          footer: {
              if !selectedChapters.isEmpty {
                  Text("Practising only selected chapters. Tap to change.")
                      .font(.caption).foregroundStyle(.secondary)
              }
          }
    }

    // MARK: Mode row

    private func isAvailable(_ mode: PracticeMode) -> Bool {
        let count = filteredCards.count
        switch mode {
        case .flashcards, .written: return count > 0
        case .multipleChoice, .match: return count >= 4
        }
    }

    private func row(_ mode: PracticeMode) -> some View {
        HStack(spacing: 14) {
            Image(systemName: mode.systemImage)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).fontWeight(.semibold)
                Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Persistence

    private func loadSavedChapters() {
        if let data = UserDefaults.standard.data(forKey: deckChapterKey),
           let saved = try? JSONDecoder().decode(Set<String>.self, from: data) {
            selectedChapters = saved
        }
    }

    private func saveChapters() {
        if let data = try? JSONEncoder().encode(selectedChapters) {
            UserDefaults.standard.set(data, forKey: deckChapterKey)
        }
    }

    private func chapterNames() -> [String: String] {
        var map: [String: String] = [:]
        for card in deck.cards where !card.chapter.isEmpty {
            map[card.chapter] = card.chapterName.isEmpty ? card.chapter : card.chapterName
        }
        return map
    }
}

// MARK: - Chapter picker sheet

struct ChapterPickerSheet: View {
    let chapters: [String]
    let chapterNames: [String: String]
    @Binding var selected: Set<String>
    let deck: Deck
    @Environment(\.dismiss) private var dismiss

    private func cardCount(_ chapter: String) -> Int {
        deck.cards.filter { $0.chapter == chapter }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if selected.count == chapters.count { selected.removeAll() }
                        else { selected = Set(chapters) }
                    } label: {
                        let all = selected.count == chapters.count
                        Label(
                            all ? "Deselect all" : "Select all chapters",
                            systemImage: all ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(.tint)
                    }
                }

                Section("Chapters") {
                    ForEach(chapters, id: \.self) { ch in
                        Button {
                            if selected.contains(ch) { selected.remove(ch) }
                            else { selected.insert(ch) }
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(ch) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(ch) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapterNames[ch] ?? ch)
                                        .foregroundStyle(.primary)
                                    Text("\(cardCount(ch)) cards")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Choose Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - DifficultyPicker (unchanged, kept here)

struct DifficultyPicker: View {
    @Bindable var card: Card

    var body: some View {
        Menu {
            Picker("Difficulty", selection: $card.userDifficulty) {
                Text("Unclassified").tag(0)
                Text("Easy").tag(1)
                Text("Medium").tag(2)
                Text("Hard").tag(3)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: card.userDifficulty == 0 ? "flag" : "flag.fill")
                if card.userDifficulty != 0 {
                    Text(difficultyLabel).font(.caption2).fontWeight(.semibold)
                }
            }
            .foregroundStyle(difficultyColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(difficultyColor.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    private var difficultyLabel: String {
        switch card.userDifficulty {
        case 1: return "Easy"
        case 2: return "Med"
        case 3: return "Hard"
        default: return ""
        }
    }

    private var difficultyColor: Color {
        switch card.userDifficulty {
        case 1: return Theme.success
        case 2: return .orange
        case 3: return Theme.destructive
        default: return .secondary
        }
    }
}
