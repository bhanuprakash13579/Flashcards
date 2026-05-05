import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "rectangle.on.rectangle.angled",
            iconColor: .accentColor,
            title: "Welcome to Flashcards",
            body: "The smartest way to prepare for EPFO APFC and other competitive exams. Science-backed spaced repetition schedules your reviews at exactly the right time so you remember more with less effort."
        ),
        OnboardingPage(
            icon: "brain.head.profile",
            iconColor: .purple,
            title: "FSRS — Smarter than Anki",
            body: "Your cards are scheduled by FSRS-4.5, trained on 20 million reviews. It tracks how well your memory holds each card individually and spaces reviews to hit 90% retention — far more accurate than older SM-2 systems."
        ),
        OnboardingPage(
            icon: "list.bullet.rectangle",
            iconColor: .orange,
            title: "4 Practice Modes",
            body: "Flashcards with swipe grading, Multiple Choice (auto-generates smart wrong options), Written Review with fuzzy matching, and Match Pairs against the clock. Use them together — variety builds stronger memory."
        ),
        OnboardingPage(
            icon: "flag.fill",
            iconColor: Theme.stretch,
            title: "Never Forget Hard Cards",
            body: "Flag cards as Hard while practising. Turn on Never-Forget mode in Settings and every hard card comes first in every session until you've seen it today. No card left behind on exam day."
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: Theme.success,
            title: "Your Stats Drive Your Study",
            body: "The forgetting curve shows exactly which cards you'll lose over the next 30 days. The sparkline on each struggling card shows your last 10 attempts at a glance. Study smarter, not longer."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, p in
                    pageView(p).tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            // Dot indicator
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == page ? 8 : 6, height: i == page ? 8 : 6)
                        .animation(.spring(response: 0.3), value: page)
                }
            }
            .padding(.top, 16)

            // Action button
            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    hasSeenOnboarding = true
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Start studying")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 40)

            if page < pages.count - 1 {
                Button("Skip") { hasSeenOnboarding = true }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .interactiveDismissDisabled()
    }

    private func pageView(_ p: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(p.iconColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: p.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(p.iconColor)
            }
            VStack(spacing: 12) {
                Text(p.title)
                    .font(.title2).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(p.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 8)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
}
