import SwiftUI
import SwiftData

/// Cross-deck timed MCQ exam — simulates the actual competitive exam format.
/// Randomly samples questions from all (or selected) decks, enforces per-question
/// time limit, shows score + review at the end.
struct ExamSimulatorView: View {
    let allDecks: [Deck]
    @Environment(\.dismiss) private var dismiss

    // Configuration state
    @State private var questionCount = 50
    @State private var secondsPerQuestion = 60
    @State private var selectedDeckIDs: Set<UUID> = []
    @State private var examStarted = false

    var body: some View {
        NavigationStack {
            if examStarted {
                ExamSessionView(
                    questions: buildQuestions(),
                    secondsPerQuestion: secondsPerQuestion,
                    onFinish: { examStarted = false }
                )
            } else {
                configView
            }
        }
    }

    // MARK: - Config screen

    private var configView: some View {
        Form {
            Section {
                Stepper(value: $questionCount, in: 10...200, step: 10) {
                    HStack {
                        Text("Questions")
                        Spacer()
                        Text("\(questionCount)").foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $secondsPerQuestion, in: 15...120, step: 15) {
                    HStack {
                        Text("Seconds per question")
                        Spacer()
                        Text("\(secondsPerQuestion)s").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Exam settings")
            } footer: {
                let total = questionCount * secondsPerQuestion
                Text("Total time: \(total / 60)m \(total % 60)s")
            }

            Section {
                Button("All decks") { selectedDeckIDs.removeAll() }
                    .foregroundStyle(selectedDeckIDs.isEmpty ? Color.accentColor : .secondary)
                ForEach(allDecks) { deck in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: deck.colorHex))
                            .frame(width: 4, height: 20)
                        Text(deck.name)
                        Spacer()
                        Text("\(deck.cards.count) cards")
                            .font(.caption).foregroundStyle(.secondary)
                        if selectedDeckIDs.contains(deck.id) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedDeckIDs.contains(deck.id) {
                            selectedDeckIDs.remove(deck.id)
                        } else {
                            selectedDeckIDs.insert(deck.id)
                        }
                    }
                }
            } header: {
                Text("Decks to include")
            } footer: {
                Text(selectedDeckIDs.isEmpty
                     ? "Drawing from all \(allDecks.count) deck\(allDecks.count == 1 ? "" : "s")"
                     : "\(selectedDeckIDs.count) deck\(selectedDeckIDs.count == 1 ? "" : "s") selected")
            }

            Section {
                let pool = buildQuestions()
                if pool.isEmpty {
                    Text("Not enough MCQ cards in selected decks.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Start exam — \(min(questionCount, pool.count)) questions") {
                        examStarted = true
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Exam Simulator")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }

    // MARK: - Question builder

    private func buildQuestions() -> [ExamQuestion] {
        let sourceDeckIDs = selectedDeckIDs.isEmpty ? Set(allDecks.map(\.id)) : selectedDeckIDs
        let sourceDecks = allDecks.filter { sourceDeckIDs.contains($0.id) }
        let allCards = sourceDecks.flatMap(\.cards)
        // Only MCQ-capable cards (have stored options OR have ≥4 cards in pool for auto-distractors)
        let pool = allCards.filter { $0.storedMCQOptions != nil || allCards.count >= 4 }
        let picks = Array(pool.shuffled().prefix(questionCount))

        return picks.map { card in
            let correctAnswer = card.cleanMCQAnswer
            let options: [String]
            if let stored = card.storedMCQOptions {
                options = stored
            } else {
                let distractorPool = allCards.filter { $0.id != card.id }.map(\.cleanMCQAnswer)
                let distractors = PracticeQueue.distractors(for: correctAnswer, from: distractorPool, n: 3)
                options = ([correctAnswer] + distractors).shuffled()
            }
            return ExamQuestion(card: card, options: options, correctAnswer: correctAnswer)
        }
    }
}

// MARK: - Data model

struct ExamQuestion: Identifiable {
    let id = UUID()
    let card: Card
    let options: [String]
    let correctAnswer: String
    var pickedAnswer: String? = nil
}

// MARK: - Session view

private struct ExamSessionView: View {
    @State var questions: [ExamQuestion]
    let secondsPerQuestion: Int
    let onFinish: () -> Void

    @State private var index = 0
    @State private var timeLeft: Int
    @State private var timer: Timer?
    @State private var showReview = false

    init(questions: [ExamQuestion], secondsPerQuestion: Int, onFinish: @escaping () -> Void) {
        _questions = State(initialValue: questions)
        self.secondsPerQuestion = secondsPerQuestion
        self.onFinish = onFinish
        _timeLeft = State(initialValue: secondsPerQuestion)
    }

    var body: some View {
        Group {
            if showReview {
                reviewView
            } else if index < questions.count {
                questionView
            }
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Question view

    private var questionView: some View {
        let q = questions[index]
        return VStack(spacing: 0) {
            // Header bar
            VStack(spacing: 6) {
                HStack {
                    Text("\(index + 1) / \(questions.count)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    timerBadge
                }
                ProgressView(value: Double(index), total: Double(questions.count))
                    .tint(timerColor)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xs)

            ScrollView {
                VStack(spacing: Theme.Space.m) {
                    // Question card
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.l)
                            .fill(Color(.secondarySystemBackground))
                        Text(q.card.front)
                            .font(Theme.cardFace(18))
                            .multilineTextAlignment(.center)
                            .padding(Theme.Space.l)
                    }
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.top, Theme.Space.s)

                    // Options
                    VStack(spacing: Theme.Space.s) {
                        ForEach(q.options, id: \.self) { opt in
                            Button { pick(opt) } label: {
                                HStack {
                                    Text(opt)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let picked = q.pickedAnswer {
                                        if opt == q.correctAnswer {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                        } else if opt == picked {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.stretch)
                                        }
                                    }
                                }
                                .padding(.vertical, 12).padding(.horizontal, 14)
                                .background(optionBackground(opt, q: q), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                            }
                            .buttonStyle(.plain)
                            .disabled(q.pickedAnswer != nil)
                        }
                    }
                    .padding(.horizontal, Theme.Space.m)

                    // Explanation + Next
                    if q.pickedAnswer != nil {
                        if let expl = q.card.explanation {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(q.pickedAnswer == q.correctAnswer ? "Explanation" : "Incorrect — Explanation")
                                    .font(.caption.bold())
                                    .foregroundStyle(q.pickedAnswer == q.correctAnswer ? Theme.success : Theme.stretch)
                                Text(expl).font(.callout).foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                            .padding(.horizontal, Theme.Space.m)
                        }

                        Button { advance() } label: {
                            Text(index + 1 < questions.count ? "Next →" : "Finish")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.bottom, Theme.Space.m)
                    }
                }
            }
        }
        .navigationTitle("Exam")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("End exam") { finishEarly() }
                    .foregroundStyle(Theme.destructive)
            }
        }
        .id(index)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.easeOut(duration: 0.18), value: index)
    }

    // MARK: - Review screen

    private var reviewView: some View {
        let correct = questions.filter { $0.pickedAnswer == $0.correctAnswer }.count
        let total = questions.count
        let skipped = questions.filter { $0.pickedAnswer == nil }.count
        let pct = total > 0 ? Int(Double(correct) / Double(total) * 100) : 0

        return ScrollView {
            VStack(spacing: Theme.Space.m) {
                // Score header
                VStack(spacing: Theme.Space.s) {
                    ZStack {
                        Circle().stroke(Color(.tertiarySystemFill), lineWidth: 10).frame(width: 110, height: 110)
                        Circle()
                            .trim(from: 0, to: Double(pct) / 100)
                            .stroke(scoreColor(pct), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 110, height: 110)
                        VStack(spacing: 2) {
                            Text("\(pct)%").font(.title.bold()).foregroundStyle(scoreColor(pct))
                            Text("score").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text("\(correct) / \(total) correct\(skipped > 0 ? " · \(skipped) skipped" : "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(scoreMessage(pct)).font(.headline).multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Space.l)

                Divider().padding(.horizontal, Theme.Space.m)

                // Per-question review
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Question review")
                        .font(.headline).padding(.horizontal, Theme.Space.m)
                    ForEach(questions.indices, id: \.self) { i in
                        let q = questions[i]
                        let isCorrect = q.pickedAnswer == q.correctAnswer
                        let wasSkipped = q.pickedAnswer == nil
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: wasSkipped ? "minus.circle" : (isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"))
                                    .foregroundStyle(wasSkipped ? .secondary : (isCorrect ? Theme.success : Theme.stretch))
                                Text("\(i + 1). \(q.card.front)")
                                    .font(.subheadline).lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !isCorrect && !wasSkipped {
                                Text("Correct: \(q.correctAnswer)")
                                    .font(.caption).foregroundStyle(Theme.success)
                                    .padding(.leading, 28)
                            }
                        }
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.vertical, 6)
                        .background(
                            (isCorrect ? Theme.success : wasSkipped ? Color.secondary : Theme.stretch).opacity(0.07),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.m)
                        )
                        .padding(.horizontal, Theme.Space.m)
                    }
                }
                .padding(.bottom, Theme.Space.xl)

                Button("Done") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, Theme.Space.l)
            }
        }
        .navigationTitle("Exam Results")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Timer

    private var timerBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.caption2)
            Text("\(timeLeft)s").font(.footnote.monospacedDigit())
        }
        .foregroundStyle(timerColor)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(timerColor.opacity(0.12), in: Capsule())
    }

    private var timerColor: Color {
        if timeLeft > secondsPerQuestion / 2 { return Theme.success }
        if timeLeft > secondsPerQuestion / 4 { return .orange }
        return Theme.stretch
    }

    private func startTimer() {
        timer?.invalidate()
        timeLeft = secondsPerQuestion
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if timeLeft > 0 {
                timeLeft -= 1
            } else {
                // Time's up — auto-advance with no answer
                advance()
            }
        }
    }

    // MARK: - Logic

    private func pick(_ opt: String) {
        guard index < questions.count, questions[index].pickedAnswer == nil else { return }
        questions[index].pickedAnswer = opt
        timer?.invalidate()
        // Rate the underlying card via SM-2
        let card = questions[index].card
        let wasNew = card.isNew
        if opt == questions[index].correctAnswer {
            card.rate(4)
        } else {
            card.rate(2)
        }
        StudyHistory.recordReview()
        if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
    }

    private func advance() {
        timer?.invalidate()
        if index + 1 < questions.count {
            withAnimation(.easeOut(duration: 0.18)) { index += 1 }
            startTimer()
        } else {
            withAnimation { showReview = true }
        }
    }

    private func finishEarly() {
        timer?.invalidate()
        withAnimation { showReview = true }
    }

    private func optionBackground(_ opt: String, q: ExamQuestion) -> Color {
        guard let picked = q.pickedAnswer else { return Color(.secondarySystemBackground) }
        if opt == q.correctAnswer { return Theme.success.opacity(0.15) }
        if opt == picked { return Theme.stretch.opacity(0.15) }
        return Color(.secondarySystemBackground)
    }

    private func scoreColor(_ pct: Int) -> Color {
        pct >= 80 ? Theme.success : pct >= 60 ? .orange : Theme.stretch
    }

    private func scoreMessage(_ pct: Int) -> String {
        switch pct {
        case 90...: return "Outstanding! Exam-ready."
        case 80...: return "Strong performance. Keep revising hard cards."
        case 60...: return "Good base — focus on your weak areas."
        default:    return "More practice needed. Review struggling cards daily."
        }
    }
}

// MARK: - Spacing extension

private extension Theme {
    static let xl: CGFloat = 32
}
