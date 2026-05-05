import SwiftUI
import SwiftData

struct AICardGeneratorView: View {
    let deck: Deck
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @AppStorage("claudeAPIKey") private var apiKey = ""

    @State private var topic = ""
    @State private var cardCount = 10
    @State private var mode: ClaudeService.GenerationMode = .flashcard
    @State private var isGenerating = false
    @State private var generated: [ClaudeService.GeneratedCard] = []
    @State private var selected: Set<Int> = []
    @State private var errorMessage: String?
    @State private var showAPIKeyEntry = false
    @State private var apiKeyDraft = ""
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if apiKey.isEmpty {
                    apiKeySection
                } else {
                    inputSection
                    if !generated.isEmpty {
                        previewSection
                    }
                }
            }
            .navigationTitle("AI Card Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !generated.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selected.count)") { addSelected() }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .overlay {
                if isGenerating {
                    generatingOverlay
                }
            }
            .alert("Done", isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            ), presenting: resultMessage) { _ in
                Button("OK") { resultMessage = nil; if !generated.isEmpty { dismiss() } }
            } message: { msg in Text(msg) }
        }
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Claude API Key Required", systemImage: "key.fill")
                    .font(.headline)
                Text("AI card generation uses Claude (Anthropic). Get a free API key at console.anthropic.com, then paste it here.")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField("sk-ant-…", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save API key") {
                    apiKey = apiKeyDraft.trimmingCharacters(in: .whitespaces)
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Setup")
        }
    }

    private var inputSection: some View {
        Group {
            Section {
                HStack {
                    Text("API key")
                    Spacer()
                    Text("••••••\(String(apiKey.suffix(4)))")
                        .foregroundStyle(.secondary).font(.caption)
                    Button("Change") { apiKey = "" }
                        .font(.caption)
                }
            }

            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(ClaudeService.GenerationMode.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }

                Stepper(value: $cardCount, in: 3...50, step: 5) {
                    HStack {
                        Text("Cards to generate")
                        Spacer()
                        Text("\(cardCount)").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Options")
            }

            Section {
                TextEditor(text: $topic)
                    .frame(minHeight: 120)
                    .font(.body)
            } header: {
                Text("Topic or text passage")
            } footer: {
                Text("Describe a topic (\"Indian Constitution — Fundamental Rights\") or paste a passage of text. Claude will generate \(cardCount) \(mode == .mcq ? "MCQ questions" : "Q&A flashcards") from it.")
            }

            Section {
                Button {
                    generate()
                } label: {
                    Label("Generate cards", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .disabled(topic.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                .buttonStyle(.borderedProminent)
            }

            if let err = errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.destructive)
                        .font(.caption)
                }
            }
        }
    }

    private var previewSection: some View {
        Section {
            HStack {
                Text("\(generated.count) cards generated")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button(selected.count == generated.count ? "Deselect all" : "Select all") {
                    if selected.count == generated.count {
                        selected = []
                    } else {
                        selected = Set(generated.indices)
                    }
                }
                .font(.caption)
            }
            ForEach(Array(generated.enumerated()), id: \.offset) { idx, card in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: selected.contains(idx) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(idx) ? Color.accentColor : .secondary)
                        .font(.title3)
                        .onTapGesture {
                            if selected.contains(idx) { selected.remove(idx) }
                            else { selected.insert(idx) }
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.front)
                            .font(.body).fontWeight(.medium)
                            .lineLimit(3)
                        Text(card.back)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                        if let o1 = card.option1 {
                            Text("Options: \(o1)\(card.option2 != nil ? ", \(card.option2!)" : "")\(card.option3 != nil ? ", \(card.option3!)" : "")")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(idx) { selected.remove(idx) }
                    else { selected.insert(idx) }
                }
            }
        } header: {
            Text("Preview — tap to select")
        }
    }

    private var generatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                Text("Generating with Claude…")
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.medium))
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Actions

    private func generate() {
        let t = topic.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        generated = []
        selected = []
        Task {
            defer { isGenerating = false }
            do {
                let cards = try await ClaudeService.generateCards(
                    topic: t,
                    count: cardCount,
                    mode: mode,
                    apiKey: apiKey
                )
                generated = cards
                selected = Set(cards.indices)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addSelected() {
        let toAdd = selected.sorted().map { generated[$0] }
        for g in toAdd {
            let card = Card(front: g.front, back: g.back, deck: deck)
            card.option1 = g.option1
            card.option2 = g.option2
            card.option3 = g.option3
            ctx.insert(card)
        }
        try? ctx.save()
        resultMessage = "Added \(toAdd.count) card\(toAdd.count == 1 ? "" : "s") to \(deck.name)."
    }
}
