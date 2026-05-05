import SwiftUI
import SwiftData

struct MatchView: View {
    let deck: Deck
    var cardFilter: PracticeQueue.CardFilter = .all
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit
    @AppStorage("neverForgetEnabled") private var neverForgetEnabled = false
    private let maxPairsPerRound = 6
    private let minPairsRequired = 4

    @State private var roundCards: [Card] = []
    @State private var fronts: [Tile] = []
    @State private var backs: [Tile] = []
    @State private var selectedFront: UUID?
    @State private var selectedBack: UUID?
    @State private var matched: Set<UUID> = []
    @State private var wrongFlash: (front: UUID, back: UUID)?
    @State private var mistakes = 0
    @State private var startTime = Date()
    @State private var roundDone = false

    struct Tile: Identifiable, Equatable {
        let id: UUID
        let text: String
    }

    var body: some View {
        Group {
            if roundCards.isEmpty { emptyState }
            else if roundDone { summary }
            else { gameBoard }
        }
        .navigationTitle("Match pairs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startRound() }
    }

    private func startRound() {
        var pool = PracticeQueue.ordered(
            deck.cards,
            onlyDue: true,
            roundSize: nil,
            filter: cardFilter,
            dailyNewCardLimit: dailyNewCardLimit,
            neverForgetEnabled: neverForgetEnabled
        )
        if pool.count < minPairsRequired {
            pool = PracticeQueue.ordered(
                deck.cards,
                onlyDue: false,
                roundSize: nil,
                filter: cardFilter,
                dailyNewCardLimit: dailyNewCardLimit,
                neverForgetEnabled: neverForgetEnabled
            )
        }
        // Use however many we have, up to maxPairsPerRound (minimum 4 to play)
        let pairCount = min(pool.count, maxPairsPerRound)
        let picks = Array(pool.prefix(pairCount))
        roundCards = picks
        fronts = picks.map { Tile(id: $0.id, text: $0.front) }
        backs = picks.map { Tile(id: $0.id, text: $0.back) }.shuffled()
        selectedFront = nil
        selectedBack = nil
        matched = []
        mistakes = 0
        wrongFlash = nil
        startTime = Date()
        roundDone = false
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "square.grid.2x2").font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Need at least \(minPairsRequired) cards.").font(.headline)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private var summary: some View {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        return VStack(spacing: Theme.Space.m) {
            Image(systemName: "sparkles").font(.system(size: 56))
                .foregroundStyle(Theme.focus)
            Text(Encouragement.random(Encouragement.sessionDone))
                .font(.title3).fontWeight(.semibold)
            Text("\(elapsed)s · \(mistakes) miss\(mistakes == 1 ? "" : "es")")
                .foregroundStyle(.secondary)
            HStack {
                Button("Done") { dismiss() }.buttonStyle(.bordered)
                Button("Next round") { startRound() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var gameBoard: some View {
        VStack(spacing: Theme.Space.s) {
            HStack {
                Text("Pairs left: \(roundCards.count - matched.count)").font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if mistakes > 0 {
                    Text("Misses: \(mistakes)").font(.footnote)
                        .foregroundStyle(Theme.stretch)
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.xs)

            HStack(alignment: .top, spacing: Theme.Space.s) {
                column(fronts, isFront: true)
                column(backs, isFront: false)
            }
            .padding(.horizontal, Theme.Space.s)
        }
    }

    private func column(_ tiles: [Tile], isFront: Bool) -> some View {
        VStack(spacing: Theme.Space.s) {
            ForEach(tiles) { tile in
                tileButton(tile, isFront: isFront)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func tileButton(_ tile: Tile, isFront: Bool) -> some View {
        let selected = isFront ? selectedFront == tile.id : selectedBack == tile.id
        let isMatched = matched.contains(tile.id)
        let isFlashing = wrongFlash?.front == tile.id || wrongFlash?.back == tile.id

        return Button {
            tap(tile, isFront: isFront)
        } label: {
            Text(tile.text)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(8)
                .background(background(selected: selected, matched: isMatched, flashing: isFlashing),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .foregroundStyle(isMatched ? Color.secondary : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(isMatched)
        .opacity(isMatched ? 0.35 : 1)
        .animation(.easeOut(duration: 0.12), value: matched)
        .animation(.easeOut(duration: 0.1), value: wrongFlash?.front)
    }

    private func background(selected: Bool, matched: Bool, flashing: Bool) -> Color {
        if flashing { return Theme.chip(Theme.stretch) }
        if matched  { return Color(.tertiarySystemBackground) }
        if selected { return Theme.chip(Color(hex: deck.colorHex)) }
        return Color(.secondarySystemBackground)
    }

    private func tap(_ tile: Tile, isFront: Bool) {
        guard !matched.contains(tile.id) else { return }
        if isFront { selectedFront = tile.id } else { selectedBack = tile.id }
        if let f = selectedFront, let b = selectedBack {
            evaluate(frontId: f, backId: b)
        }
    }

    private func evaluate(frontId: UUID, backId: UUID) {
        if frontId == backId {
            matched.insert(frontId)
            selectedFront = nil
            selectedBack = nil
            HapticService.match()
            if let card = roundCards.first(where: { $0.id == frontId }) {
                let wasNew = card.isNew
                card.rate(4)
                StudyHistory.recordReview()
                if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
            }
            if matched.count == roundCards.count {
                roundDone = true
            }
        } else {
            mistakes += 1
            HapticService.mismatch()
            if let card = roundCards.first(where: { $0.id == frontId }) {
                card.rate(2)
                StudyHistory.recordReview()
            }
            wrongFlash = (frontId, backId)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                self.wrongFlash = nil
                self.selectedFront = nil
                self.selectedBack = nil
            }
        }
    }
}
