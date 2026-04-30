import SwiftUI
import SwiftData

struct MultipleChoiceView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var options: [String] = []
    @State private var correctAnswer: String = ""
    @State private var displayQuestion: String = ""   // question text sans embedded options
    @State private var picked: String?
    @State private var rightCount = 0
    @State private var wrongCount = 0

    var body: some View {
        Group {
            if queue.isEmpty {
                emptyState
            } else if index >= queue.count {
                summary
            } else {
                questionView
            }
        }
        .navigationTitle("Multiple choice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadQueue)
    }

    private func loadQueue() {
        guard deck.cards.count >= 4 else { return }
        var q = PracticeQueue.ordered(
            deck.cards,
            onlyDue: true,
            dailyNewCardLimit: dailyNewCardLimit,
            roundSize: PracticeQueue.defaultRoundSize
        )
        if q.isEmpty {
            q = PracticeQueue.ordered(
                deck.cards,
                onlyDue: false,
                dailyNewCardLimit: dailyNewCardLimit,
                roundSize: PracticeQueue.defaultRoundSize
            )
        }
        queue = q
        index = 0
        rightCount = 0
        wrongCount = 0
        prepareCurrent()
    }

    private func prepareCurrent() {
        guard index < queue.count else { return }
        let card = queue[index]

        if let parsed = parseEmbeddedOptions(card) {
            // Card already has (A)-(D) — use them directly
            displayQuestion = parsed.question
            correctAnswer = parsed.correct
            options = parsed.options.shuffled()
        } else {
            // Plain Q&A card — build distractors from other cards' backs
            displayQuestion = card.front
            correctAnswer = card.back
            let pool = deck.cards.filter { $0.id != card.id }.map(\.back)
            let distractors = PracticeQueue.distractors(for: correctAnswer, from: pool, n: 3)
            options = ([correctAnswer] + distractors).shuffled()
        }
        picked = nil
    }

    // MARK: - Embedded option parser

    private struct ParsedOptions {
        let question: String
        let options: [String]   // all 4 option texts (A, B, C, D in order)
        let correct: String     // the correct option's text
    }

    private func parseEmbeddedOptions(_ card: Card) -> ParsedOptions? {
        let front = card.front
        guard front.contains("(A)") else { return nil }

        // Question body = everything before first "(A)"
        guard let aRange = front.range(of: "(A)") else { return nil }
        let questionText = String(front[..<aRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract option texts with a simple split on "(A)", "(B)", "(C)", "(D)"
        let markers: [(Character, String)] = [("A","(A)"),("B","(B)"),("C","(C)"),("D","(D)")]
        var optionsByLetter: [Character: String] = [:]

        for (idx, (letter, marker)) in markers.enumerated() {
            guard let start = front.range(of: marker) else { return nil }
            let textStart = start.upperBound
            let textEnd: String.Index
            if idx + 1 < markers.count {
                let nextMarker = markers[idx + 1].1
                textEnd = front.range(of: nextMarker, range: textStart..<front.endIndex)?.lowerBound ?? front.endIndex
            } else {
                textEnd = front.endIndex
            }
            let text = String(front[textStart..<textEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            optionsByLetter[letter] = text
        }

        guard optionsByLetter.count == 4 else { return nil }
        let allOptions = ["A","B","C","D"].compactMap { optionsByLetter[$0.first!] }
        guard allOptions.count == 4 else { return nil }

        // Determine correct letter from card.back — expects "(X) ..." or "X ..."
        let back = card.back.trimmingCharacters(in: .whitespaces)
        let correctLetter: Character?
        if back.hasPrefix("("), back.count >= 2 {
            correctLetter = back[back.index(after: back.startIndex)]
        } else if let first = back.first, "ABCD".contains(first) {
            correctLetter = first
        } else {
            correctLetter = nil
        }

        guard let cl = correctLetter, let correctText = optionsByLetter[cl] else { return nil }
        return ParsedOptions(question: questionText, options: allOptions, correct: correctText)
    }

    // MARK: - Views

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "list.bullet.rectangle").font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Need at least 4 cards in this deck.").font(.headline)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private var summary: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "sparkles").font(.system(size: 56))
                .foregroundStyle(Theme.focus)
            Text(Encouragement.random(Encouragement.sessionDone))
                .font(.title3).fontWeight(.semibold)
            Text("\(rightCount) right · \(wrongCount) missed").foregroundStyle(.secondary)
            HStack {
                Button("Done") { dismiss() }.buttonStyle(.bordered)
                Button("Another round") { loadQueue() }.buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var questionView: some View {
        let card = queue[index]
        return VStack(spacing: Theme.Space.m) {
            progress

            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.l)
                    .fill(Theme.surface(Color(hex: deck.colorHex)))
                VStack(spacing: Theme.Space.s) {
                    if let data = card.frontImageData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 140)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                    }
                    Text(displayQuestion)
                        .font(Theme.cardFace(20))
                        .multilineTextAlignment(.center)
                }
                .padding(Theme.Space.l)
            }
            .frame(minHeight: 160)
            .padding(.horizontal, Theme.Space.m)

            VStack(spacing: Theme.Space.s) {
                ForEach(options, id: \.self) { opt in
                    Button { choose(opt, card: card) } label: {
                        HStack {
                            Text(opt)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let picked, opt == correctAnswer {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.success)
                            } else if let picked, opt == picked {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.stretch)
                            }
                        }
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .background(background(for: opt), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    }
                    .buttonStyle(.plain)
                    .disabled(picked != nil)
                }
            }
            .padding(.horizontal, Theme.Space.m)

            if picked != nil {
                Button("Next") { advance() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.bottom, Theme.Space.m)
            }
        }
    }

    private func background(for option: String) -> Color {
        guard let picked else { return Color(.secondarySystemBackground) }
        if option == correctAnswer { return Theme.surface(Theme.success) }
        if option == picked        { return Theme.surface(Theme.stretch) }
        return Color(.secondarySystemBackground)
    }

    private var progress: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(index + 1) of \(queue.count)").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("✓ \(rightCount)").font(.footnote).foregroundStyle(Theme.success)
            }
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .tint(Color(hex: deck.colorHex))
        }
        .padding(.horizontal, Theme.Space.m).padding(.top, Theme.Space.s)
    }

    private func choose(_ opt: String, card: Card) {
        guard picked == nil else { return }
        picked = opt
        let wasNew = card.isNew
        if opt == correctAnswer {
            card.rate(4)
            rightCount += 1
        } else {
            card.rate(2)
            wrongCount += 1
        }
        StudyHistory.recordReview()
        if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
    }

    private func advance() {
        index += 1
        if index < queue.count { prepareCurrent() }
    }
}
