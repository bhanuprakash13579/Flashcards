import SwiftUI

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

struct PracticeHub: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                    if deck.cards.count < 4 {
                        Text("Add at least 4 cards to unlock multiple choice and match modes.")
                    } else {
                        Text("Struggling cards (more wrong than right) appear first in every mode.")
                    }
                }
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: PracticeMode.self) { mode in
                switch mode {
                case .flashcards:     StudyView(deck: deck)
                case .multipleChoice: MultipleChoiceView(deck: deck)
                case .written:        WrittenReviewView(deck: deck)
                case .match:          MatchView(deck: deck)
                }
            }
        }
    }

    private func isAvailable(_ mode: PracticeMode) -> Bool {
        switch mode {
        case .flashcards, .written: return !deck.cards.isEmpty
        case .multipleChoice:       return deck.cards.count >= 4
        case .match:                return deck.cards.count >= 4
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
}
