import SwiftUI
import SwiftData

struct WrittenReviewView: View {
    let deck: Deck
    var cards: [Card]? = nil
    var cardFilter: PracticeQueue.CardFilter = .all
    @Environment(\.dismiss) private var dismiss
    @AppStorage("practiceRoundSize") private var practiceRoundSize = PracticeQueue.defaultRoundSize
    @AppStorage("dailyNewCardLimit") private var dailyNewCardLimit = PracticeQueue.defaultDailyNewCardLimit
    @AppStorage("neverForgetEnabled") private var neverForgetEnabled = false

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var typed = ""
    @State private var verdict: Verdict?
    @State private var rightCount = 0
    @State private var wrongCount = 0
    @State private var requeuePile: [Card] = []
    @State private var isRepass = false
    @FocusState private var typing: Bool

    enum Verdict { case exact, close, wrong }

    var body: some View {
        Group {
            if queue.isEmpty { emptyState }
            else if index >= queue.count { summary }
            else { questionView }
        }
        .navigationTitle("Written review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadQueue)
    }

    private func loadQueue() {
        let source = cards ?? deck.cards
        var q = PracticeQueue.ordered(
            source,
            onlyDue: true,
            roundSize: practiceRoundSize,
            filter: cardFilter,
            dailyNewCardLimit: dailyNewCardLimit,
            neverForgetEnabled: neverForgetEnabled
        )
        if q.isEmpty {
            q = PracticeQueue.ordered(
                source,
                onlyDue: false,
                roundSize: practiceRoundSize,
                filter: cardFilter,
                dailyNewCardLimit: dailyNewCardLimit,
                neverForgetEnabled: neverForgetEnabled
            )
        }
        queue = q
        index = 0
        rightCount = 0
        wrongCount = 0
        requeuePile = []
        isRepass = false
        resetCurrent()
    }

    private func resetCurrent() {
        typed = ""
        verdict = nil
        typing = true
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "pencil.and.outline").font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No cards in this deck yet.").font(.headline)
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private var summary: some View {
        VStack(spacing: Theme.Space.m) {
            if !isRepass && !requeuePile.isEmpty {
                Image(systemName: "arrow.clockwise").font(.system(size: 56))
                    .foregroundStyle(Theme.stretch)
                Text("\(rightCount) right · \(wrongCount) missed")
                    .font(.title3).fontWeight(.semibold)
                Text("\(requeuePile.count) card\(requeuePile.count == 1 ? "" : "s") you missed — review them once more.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Re-practice missed") { startRepass() }.buttonStyle(.borderedProminent)
                Button("Done for now") { dismiss() }.buttonStyle(.bordered)
            } else {
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
        }
        .padding()
    }

    private var questionView: some View {
        let card = queue[index]
        return VStack(spacing: Theme.Space.m) {
            progress(for: card)
            promptCard(card)
                .id(card.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            answerField
            verdictBanner(card)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            actionButtons(card)
            Spacer()
        }
        .padding(.bottom, Theme.Space.m)
        .animation(.easeOut(duration: 0.15), value: card.id)
        .animation(.easeOut(duration: 0.15), value: verdict != nil)
    }

    private func progress(for card: Card) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(index + 1) of \(queue.count)")
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                DifficultyPicker(card: card)
                Spacer()
                Text("✓ \(rightCount)").font(.footnote).foregroundStyle(Theme.success)
            }
            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                .tint(Color(hex: deck.colorHex))
        }
        .padding(.horizontal, Theme.Space.m).padding(.top, Theme.Space.s)
    }

    private func promptCard(_ card: Card) -> some View {
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
                Text(card.front)
                    .font(Theme.cardFace(22))
                    .multilineTextAlignment(.center)
            }
            .padding(Theme.Space.l)
        }
        .frame(minHeight: 160)
        .padding(.horizontal, Theme.Space.m)
    }

    private var answerField: some View {
        TextField("Your answer…", text: $typed, axis: .vertical)
            .lineLimit(1...4)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($typing)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .padding(.horizontal, Theme.Space.m)
            .submitLabel(.done)
            .onSubmit { if verdict == nil { check() } }
            .disabled(verdict != nil)
    }

    @ViewBuilder
    private func verdictBanner(_ card: Card) -> some View {
        switch verdict {
        case .exact:
            verdictRow(Theme.success, "Got it.", subtitle: nil)
        case .close:
            verdictRow(Theme.stretch, "Almost — was: \(card.back)",
                       subtitle: "Decide for yourself if that counts.")
        case .wrong:
            verdictRow(Theme.stretch, "Was: \(card.back)", subtitle: nil)
        case .none:
            EmptyView()
        }
    }

    private func verdictRow(_ tint: Color, _ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(tint)
            if let s = subtitle {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface(tint), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
        .padding(.horizontal, Theme.Space.m)
    }

    @ViewBuilder
    private func actionButtons(_ card: Card) -> some View {
        switch verdict {
        case .none:
            Button { check() } label: {
                Text("Check")
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.m)
            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
        case .exact, .wrong:
            Button { advance() } label: {
                Text("Next")
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.m)
        case .close:
            HStack(spacing: Theme.Space.s) {
                Button("Not yet") {
                    let wasNew = card.isNew
                    card.rate(2); wrongCount += 1
                    HapticService.wrong()
                    StudyHistory.recordReview()
                    if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
                    if !isRepass { requeuePile.append(card) }
                    advance()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.chip(Theme.stretch), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .foregroundStyle(Theme.stretch)
                Button("Got it") {
                    let wasNew = card.isNew
                    card.rate(4); rightCount += 1
                    HapticService.correct()
                    StudyHistory.recordReview()
                    if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
                    advance()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Theme.chip(Theme.success), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .foregroundStyle(Theme.success)
            }
            .padding(.horizontal, Theme.Space.m)
        }
    }

    // MARK: - Logic

    private func check() {
        guard verdict == nil, index < queue.count else { return }
        let card = queue[index]
        let result = grade(typed: typed, expected: card.back)
        verdict = result
        let wasNew = card.isNew
        switch result {
        case .exact:
            card.rate(4); rightCount += 1
            HapticService.correct()
            StudyHistory.recordReview()
            if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
        case .wrong:
            card.rate(2); wrongCount += 1
            HapticService.wrong()
            StudyHistory.recordReview()
            if wasNew { StudyHistory.bumpNewCardsIntroduced(by: 1) }
            if !isRepass { requeuePile.append(card) }
        case .close:
            break // user decides via the two-button banner
        }
        typing = false
    }

    private func advance() {
        withAnimation(.easeOut(duration: 0.15)) { index += 1 }
        if index < queue.count { resetCurrent() }
    }

    private func startRepass() {
        queue = requeuePile
        requeuePile = []
        isRepass = true
        index = 0
        resetCurrent()
    }

    private func grade(typed: String, expected: String) -> Verdict {
        let a = normalize(typed)
        let b = normalize(expected)
        if a == b { return .exact }
        let dist = levenshtein(a, b)
        let tolerance = max(2, b.count / 5)
        if dist <= tolerance { return .close }
        return .wrong
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)
        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                curr[j] = min(curr[j-1] + 1, prev[j] + 1, prev[j-1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }
}
