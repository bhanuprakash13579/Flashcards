import SwiftUI
import SwiftData

struct StudyView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit

    @State private var queue: [Card] = []
    @State private var index: Int = 0
    @State private var flipped: Bool = false
    @State private var dragX: CGFloat = 0
    @State private var ratedCount: Int = 0
    @State private var endMessage: String = ""

    private let swipeThreshold: CGFloat = 120

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
        .onAppear(perform: loadQueue)
    }

    // MARK: - Queue

    private func loadQueue() {
        queue = PracticeQueue.ordered(
            deck.cards,
            onlyDue: true,
            dailyNewCardLimit: dailyNewCardLimit,
            roundSize: PracticeQueue.defaultRoundSize
        )
        if queue.isEmpty {
            // Nothing due — let the user practice anything they want.
            queue = PracticeQueue.ordered(
                deck.cards,
                onlyDue: false,
                dailyNewCardLimit: dailyNewCardLimit,
                roundSize: PracticeQueue.defaultRoundSize
            )
        }
        index = 0
        flipped = false
        ratedCount = 0
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
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(Theme.focus)
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
        .padding()
    }

    // MARK: - Study area

    private var studyArea: some View {
        let card = queue[index]
        return VStack(spacing: Theme.Space.m) {
            progressBar

            cardFace(card)
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
                Text("Tap card to reveal")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.bottom, Theme.Space.l)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: flipped)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(index + 1) of \(queue.count) today")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
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
                Text(label)
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.m)

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
                Spacer(minLength: 0)

                Text(flipped ? "Rate yourself ↓" : "")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, Theme.Space.m)
                    .opacity(flipped ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) { flipped.toggle() }
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
            withAnimation(.spring) { dragX = 0 }
            return
        }
        if x > swipeThreshold {
            withAnimation(.easeOut(duration: 0.2)) { dragX = 600 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { rate(4, card: card) }
        } else if x < -swipeThreshold {
            withAnimation(.easeOut(duration: 0.2)) { dragX = -600 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { rate(2, card: card) }
        } else {
            withAnimation(.spring) { dragX = 0 }
        }
    }

    private func rate(_ quality: Int, card: Card) {
        let wasNew = card.isNew
        card.rate(quality)
        StudyHistory.recordReview()
        if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
        ratedCount += 1
        flipped = false
        dragX = 0
        index += 1
        if index >= queue.count {
            endMessage = Encouragement.random(Encouragement.sessionDone)
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
