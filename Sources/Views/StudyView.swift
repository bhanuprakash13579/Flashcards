import SwiftUI
import SwiftData

struct StudyView: View {
    let deck: Deck
    /// Optional explicit card list — used when a chapter filter or mixed-practice narrows the pool.
    var cards: [Card]? = nil
    var cardFilter: PracticeQueue.CardFilter = .all
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practiceRoundSize") private var practiceRoundSize = PracticeQueue.defaultRoundSize
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit
    @AppStorage("neverForgetEnabled") private var neverForgetEnabled = false
    @AppStorage("timedPracticeEnabled") private var timedPracticeEnabled = false

    @State private var queue: [Card] = []
    @State private var index: Int = 0
    @State private var flipped: Bool = false
    @State private var dragX: CGFloat = 0
    @State private var ratedCount: Int = 0
    @State private var endMessage: String = ""
    @State private var requeuePile: [Card] = []
    @State private var isRepass = false
    @State private var preFlipConfidence: Int? = nil
    @State private var isSpeaking = false

    // Per-card countdown timer
    @State private var timeRemaining: Int = 0
    @State private var timerTask: Task<Void, Never>? = nil

    private let swipeThreshold: CGFloat = 120

    private var sourceCards: [Card] { cards ?? deck.cards }

    var body: some View {
        Group {
            if queue.isEmpty {
                emptyState
            } else if index >= queue.count {
                finishedState
            } else {
                studyArea
            }
        }
        .navigationTitle("Practice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadQueue()
            SpotlightService.donateReviewShortcut(for: deck)
        }
        .onDisappear {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    // MARK: - Queue

    private func loadQueue() {
        queue = PracticeQueue.ordered(
            sourceCards,
            onlyDue: true,
            roundSize: practiceRoundSize,
            filter: cardFilter,
            dailyNewCardLimit: dailyNewCardLimit,
            neverForgetEnabled: neverForgetEnabled
        )
        if queue.isEmpty {
            queue = PracticeQueue.ordered(
                sourceCards,
                onlyDue: false,
                roundSize: practiceRoundSize,
                filter: cardFilter,
                dailyNewCardLimit: dailyNewCardLimit,
                neverForgetEnabled: neverForgetEnabled
            )
        }
        index = 0
        flipped = false
        ratedCount = 0
        requeuePile = []
        isRepass = false
        preFlipConfidence = nil
        startCardTimer()
    }

    // MARK: - Timer

    private func startCardTimer() {
        timerTask?.cancel()
        guard timedPracticeEnabled,
              index < queue.count else {
            timeRemaining = 0
            return
        }
        let card = queue[index]
        let limit = card.timeLimitSeconds > 0 ? card.timeLimitSeconds : defaultTimeLimit(for: card)
        guard limit > 0 else { timeRemaining = 0; return }
        timeRemaining = limit

        timerTask = Task { @MainActor in
            while timeRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                timeRemaining -= 1
                if timeRemaining == 0 && index < queue.count {
                    // Time's up — auto-flip to show answer
                    withAnimation(.easeOut(duration: 0.18)) { flipped = true }
                }
            }
        }
    }

    private func defaultTimeLimit(for card: Card) -> Int {
        switch card.questionType {
        case "arithmetic":  return 50
        case "reasoning":   return 38
        case "verbal":      return 25
        case "legal":       return 25
        case "accounting":  return 32
        case "science":     return 28
        default:            return 28
        }
    }

    // MARK: - Empty / Done

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "checkmark.seal").font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("All caught up.").font(.headline)
            Text("Come back later — your next reviews are scheduled.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var finishedState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: isRepass ? "arrow.clockwise" : "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(isRepass ? Theme.stretch : Theme.focus)
            if isRepass && !requeuePile.isEmpty {
                Text("Review again")
                    .font(.title3).fontWeight(.semibold)
                Text("\(requeuePile.count) card\(requeuePile.count == 1 ? "" : "s") you missed — let's go through them once more.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Re-practice missed cards") { startRepass() }
                    .buttonStyle(.borderedProminent)
                Button("Done for now") { dismiss() }.buttonStyle(.bordered)
            } else {
                Text(endMessage.isEmpty ? Encouragement.random(Encouragement.sessionDone) : endMessage)
                    .font(.title3).fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Text("\(ratedCount) card\(ratedCount == 1 ? "" : "s") · streak \(StudyHistory.currentStreak) day\(StudyHistory.currentStreak == 1 ? "" : "s")")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button("Done") { dismiss() }.buttonStyle(.bordered)
                    Button("Another round") { loadQueue() }.buttonStyle(.borderedProminent)
                }
                .padding(.top, Theme.Space.s)
            }
        }
        .padding()
    }

    // MARK: - Study area

    private var studyArea: some View {
        let card = queue[index]
        return VStack(spacing: Theme.Space.m) {
            // Hidden buttons wiring iPad / hardware-keyboard shortcuts.
            // Space flips; 1/2/3 rate (Hard/Got it/Easy) once the answer is showing.
            Group {
                Button("") { withAnimation(.easeOut(duration: 0.18)) { flipped.toggle() } }
                    .keyboardShortcut(KeyEquivalent(" "), modifiers: [])
                if flipped {
                    Button("") { rate(2, card: card) }.keyboardShortcut("1", modifiers: [])
                    Button("") { rate(4, card: card) }.keyboardShortcut("2", modifiers: [])
                    Button("") { rate(5, card: card) }.keyboardShortcut("3", modifiers: [])
                }
            }
            .frame(width: 0, height: 0)
            .opacity(0)

            progressBar(for: card)

            cardFace(card)
                .id(card.id)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
                .padding(.horizontal, Theme.Space.m)
                .offset(x: dragX)
                .rotationEffect(.degrees(Double(dragX) / 40))
                .gesture(
                    DragGesture()
                        .onChanged { v in dragX = v.translation.width }
                        .onEnded { v in handleSwipe(v.translation.width, card: card) }
                )
                .overlay(swipeBadges)

            if flipped {
                qualityButtons(for: card)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.bottom, Theme.Space.m)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                // Generation effect: nudge for unseen cards
                if card.isNew {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").foregroundStyle(.orange).font(.caption2)
                        Text("New card — make a prediction before flipping")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                confidencePrompt
                    .padding(.bottom, Theme.Space.l)
            }
        }
        .animation(.easeOut(duration: 0.14), value: flipped)
    }

    private func progressBar(for card: Card) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(index + 1) of \(queue.count) today")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                // Per-card countdown (only when timed practice is on and timer is running)
                if timedPracticeEnabled && timeRemaining > 0 {
                    TimerBadge(seconds: timeRemaining,
                               total: card.timeLimitSeconds > 0 ? card.timeLimitSeconds : defaultTimeLimit(for: card))
                }
                Spacer()
                DifficultyPicker(card: card)
                if StudyHistory.currentStreak > 0 {
                    Label("\(StudyHistory.currentStreak)d", systemImage: "flame.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.streak)
                }
            }
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .tint(Color(hex: deck.colorHex))
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.top, Theme.Space.s)
    }

    private func cardFace(_ card: Card) -> some View {
        let imageData = flipped ? card.backImageData : card.frontImageData
        let label = flipped ? "ANSWER" : "QUESTION"
        let text  = flipped ? card.back : card.front

        return ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .fill(Theme.surface(Color(hex: deck.colorHex)))
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .strokeBorder(Color(hex: deck.colorHex).opacity(0.35), lineWidth: 1)

            VStack(spacing: Theme.Space.m) {
                HStack {
                    Text(label)
                        .font(Theme.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if isSpeaking { TTSService.stop(); isSpeaking = false }
                        else { TTSService.speak(text); isSpeaking = true }
                        HapticService.tap()
                    } label: {
                        Image(systemName: isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, Theme.Space.m)
                .padding(.horizontal, Theme.Space.m)

                if let data = imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
                        .padding(.horizontal, Theme.Space.l)
                }

                Spacer(minLength: 0)
                Text(text)
                    .font(Theme.cardFace())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.l)

                // Inline explanation when answer is showing (elaboration effect)
                if flipped, let expl = card.storedExplanation, !expl.isEmpty {
                    Divider().padding(.horizontal, Theme.Space.l)
                    Text(expl)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.l)
                }
                Spacer(minLength: 0)

                if flipped {
                    Text("Think: why is this the correct answer?")
                        .font(.caption2).foregroundStyle(.tertiary).italic()
                        .padding(.bottom, 2)
                }
                Text(flipped ? "Rate yourself ↓" : "")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, Theme.Space.m)
                    .opacity(flipped ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { flipped.toggle() }
        }
    }

    private func qualityButtons(for card: Card) -> some View {
        HStack(spacing: Theme.Space.s) {
            qualityButton(label: "Hard",   tint: Theme.stretch, quality: 2, card: card)
            qualityButton(label: "Got it", tint: Theme.success, quality: 4, card: card)
            qualityButton(label: "Easy",   tint: Theme.focus,   quality: 5, card: card)
        }
    }

    private func qualityButton(label: String, tint: Color, quality: Int, card: Card) -> some View {
        Button {
            rate(quality, card: card)
        } label: {
            Text(label)
                .font(.subheadline).fontWeight(.semibold)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.chip(tint), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confidence prompt (metacognitive calibration)

    private var confidencePrompt: some View {
        VStack(spacing: Theme.Space.xs) {
            Text("Do you know this?")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.s) {
                confidenceButton(label: "No",     color: Theme.stretch,  value: 1)
                confidenceButton(label: "Unsure", color: .orange,        value: 2)
                confidenceButton(label: "Yes",    color: Theme.success,  value: 3)
            }
            .padding(.horizontal, Theme.Space.l)
        }
        .transition(.opacity)
    }

    private func confidenceButton(label: String, color: Color, value: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.1)) { preFlipConfidence = value }
            withAnimation(.easeOut(duration: 0.18)) { flipped = true }
        } label: {
            Text(label)
                .font(.subheadline).fontWeight(.medium)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(
                    preFlipConfidence == value ? color.opacity(0.25) : color.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.m)
                )
                .foregroundStyle(color)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .stroke(preFlipConfidence == value ? color : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var swipeBadges: some View {
        HStack {
            Text("HARD").font(.headline.bold())
                .padding(8)
                .background(Theme.stretch.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .opacity(Double(max(0, -dragX) / swipeThreshold).clamped(to: 0...1))
            Spacer()
            Text("GOT IT").font(.headline.bold())
                .padding(8)
                .background(Theme.success.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .opacity(Double(max(0, dragX) / swipeThreshold).clamped(to: 0...1))
        }
        .padding(.horizontal, Theme.Space.l)
        .allowsHitTesting(false)
    }

    // MARK: - Logic

    private func handleSwipe(_ x: CGFloat, card: Card) {
        guard flipped else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragX = 0 }
            return
        }
        if x > swipeThreshold {
            withAnimation(.easeOut(duration: 0.15)) { dragX = 600 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { rate(4, card: card) }
        } else if x < -swipeThreshold {
            withAnimation(.easeOut(duration: 0.15)) { dragX = -600 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { rate(2, card: card) }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { dragX = 0 }
        }
    }

    private func rate(_ quality: Int, card: Card) {
        let wasNew = card.isNew
        // Metacognitive calibration: adjust quality based on pre-flip confidence.
        // Overconfident (Yes + Hard) → harder penalty; Pleasant surprise (No + Easy) → bonus.
        let adjustedQuality: Int
        if let c = preFlipConfidence {
            switch (c, quality) {
            case (3, 2): adjustedQuality = 1  // said Yes, got it Hard → real lapse
            case (1, 5): adjustedQuality = 4  // said No, got it Easy → surprised recall, cap bonus
            default:     adjustedQuality = quality
            }
        } else {
            adjustedQuality = quality
        }
        TTSService.stop()
        isSpeaking = false
        if let c = preFlipConfidence {
            CalibrationStore.record(confidence: c, wasCorrect: adjustedQuality >= 3)
        }
        card.rate(adjustedQuality)
        if adjustedQuality >= 3 { HapticService.correct() } else { HapticService.wrong() }
        StudyHistory.recordReview()
        if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
        ratedCount += 1
        // Collect failures for re-pass (only on first pass to avoid infinite loop)
        if quality < 3 && !isRepass {
            requeuePile.append(card)
        }
        withAnimation(.easeOut(duration: 0.12)) {
            flipped = false
            dragX = 0
            index += 1
            preFlipConfidence = nil
        }
        if index >= queue.count && !isRepass {
            endMessage = Encouragement.random(Encouragement.sessionDone)
            timerTask?.cancel()
            timeRemaining = 0
        } else {
            startCardTimer()
        }
    }

    private func startRepass() {
        queue = requeuePile
        requeuePile = []
        isRepass = true
        index = 0
        flipped = false
    }
}

// MARK: - Timer badge

private struct TimerBadge: View {
    let seconds: Int
    let total: Int

    private var fraction: Double { total > 0 ? Double(seconds) / Double(total) : 1 }

    private var tint: Color {
        if fraction > 0.5 { return .green }
        if fraction > 0.25 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 22, height: 22)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 22, height: 22)
                    .animation(.linear(duration: 1), value: fraction)
            }
            Text("\(seconds)s")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
