import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - CardSpec

/// Carries all data for one card to be imported, including optional MCQ wrong-answer options.
struct CardSpec {
    var front: String
    var back: String          // always the correct answer
    var option1: String? = nil
    var option2: String? = nil
    var option3: String? = nil
    var explanation: String? = nil

    var hasMCQOptions: Bool { option1 != nil }
    var optionCount: Int { [option1, option2, option3].compactMap { $0 }.count }
}

// MARK: - BulkImportView

struct BulkImportView: View {
    let deck: Deck
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    enum ImportMode: String, CaseIterable, Identifiable {
        case text = "Text / CSV"
        case json = "JSON"
        var id: String { rawValue }
    }

    enum Delimiter: String, CaseIterable, Identifiable {
        case tab    = "Tab"
        case comma  = "Comma"
        case pipe   = "Pipe ( | )"
        case dcolon = "Double colon ( :: )"
        var id: String { rawValue }
        var character: String {
            switch self {
            case .tab:    return "\t"
            case .comma:  return ","
            case .pipe:   return "|"
            case .dcolon: return "::"
            }
        }
    }

    @State private var pastedText = ""
    @State private var delimiter: Delimiter = .tab
    @State private var showFilePicker = false
    @State private var unmappedJSONObjects: [[String: Any]]?
    @State private var importedFileName: String?
    @State private var resultMessage: String?
    @State private var parsedSpecs: [CardSpec] = []
    @State private var parseError: String?
    @State private var showFormatGuide = false
    @State private var isParsing = false
    @State private var isImporting = false
    @State private var parseTask: Task<Void, Never>? = nil
    @State private var pendingMCQBlocks: [RawMCQBlock] = []
    @State private var showMCQAnswerPicker = false

    var body: some View {
        mainForm
            .sheet(isPresented: $showFormatGuide) { FormatGuideView() }
            .sheet(isPresented: Binding(
                get: { unmappedJSONObjects != nil },
                set: { if !$0 { unmappedJSONObjects = nil } }
            )) { unmappedSheet }
            .sheet(isPresented: $showMCQAnswerPicker) { mcqPickerSheet }
    }

    @ViewBuilder private var unmappedSheet: some View {
        if let objs = unmappedJSONObjects {
            JSONMappingView(unmappedObjects: objs) { specs in
                unmappedJSONObjects = nil
                parsedSpecs.append(contentsOf: specs)
                if parseError != nil { parseError = nil }
            } onCancel: {
                unmappedJSONObjects = nil
            }
        }
    }

    @ViewBuilder private var mcqPickerSheet: some View {
        TextMCQAnswerPickerView(blocks: pendingMCQBlocks) { specs in
            parsedSpecs.append(contentsOf: specs)
            pendingMCQBlocks = []
            showMCQAnswerPicker = false
        } onCancel: {
            pendingMCQBlocks = []
            showMCQAnswerPicker = false
        }
    }

    private var mainForm: some View {
        NavigationStack {
            Form {
                importContent
            }
            .navigationTitle("Bulk import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFormatGuide = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(parsedSpecs.count)") { runImport() }
                        .disabled(parsedSpecs.isEmpty || isImporting || isParsing)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .commaSeparatedText, .tabSeparatedText, .json],
                allowsMultipleSelection: true,
                onCompletion: handlePickedFile
            )
            .alert("Done", isPresented: .constant(resultMessage != nil), presenting: resultMessage) { _ in
                Button("OK") { resultMessage = nil; dismiss() }
            } message: { msg in Text(msg) }
            .overlay {
                if isParsing || isImporting {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(1.4)
                            Text(isImporting ? "Importing cards…" : "Reading data…")
                                .foregroundStyle(.white)
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .onChange(of: pastedText) { _, new in
                if importedFileName != nil { return }
                
                if new.count > 100_000 {
                    Task { @MainActor in
                        pastedText = ""
                        parseError = "Text is too large to paste directly! Please use the 'Choose file' button above to safely load massive files."
                    }
                    return
                }
                
                if new.isEmpty { parsedSpecs = []; parseError = nil; return }
                
                parseTask?.cancel()
                parseTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    if Task.isCancelled { return }
                    
                    await MainActor.run { isParsing = true; parseError = nil }
                    
                    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    let isJson = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
                    
                    if isJson {
                        guard let data = trimmed.data(using: .utf8) else {
                            await MainActor.run {
                                parseError = "Invalid UTF-8 text."
                                parsedSpecs = []
                                isParsing = false
                            }
                            return
                        }
                        do {
                            let specs = try await Task.detached { try Self.parseJSONData(data) }.value
                            if Task.isCancelled { return }
                            if specs.isEmpty {
                                // Unknown structure — try mapping view
                                let flatObjs = Self.extractFlatObjects(from: data)
                                if !flatObjs.isEmpty {
                                    await MainActor.run {
                                        unmappedJSONObjects = flatObjs
                                        parsedSpecs = []
                                        parseError = nil
                                        isParsing = false
                                    }
                                    return
                                }
                            }
                            await MainActor.run {
                                parsedSpecs = specs
                                parseError = specs.isEmpty ? "No cards found — check the format or tap ? for examples." : nil
                                isParsing = false
                            }
                        } catch {
                            if Task.isCancelled { return }
                            await MainActor.run {
                                parseError = "JSON parse error: \(error.localizedDescription)"
                                parsedSpecs = []
                                isParsing = false
                            }
                        }
                    } else {
                        let d = delimiter.character
                        let specs = await Task.detached { Self.parseCSV(new, delimiter: d) }.value
                        if Task.isCancelled { return }

                        if specs.isEmpty && Self.looksLikeMCQ(new) {
                            let blocks = await Task.detached { Self.parseTextMCQ(new) }.value
                            if Task.isCancelled { return }
                            await MainActor.run {
                                Self.applyMCQBlocks(blocks, to: &self.parsedSpecs, pending: &self.pendingMCQBlocks, show: &self.showMCQAnswerPicker, error: &self.parseError)
                                isParsing = false
                            }
                        } else {
                            await MainActor.run {
                                parsedSpecs = specs
                                parseError = specs.isEmpty ? "No valid cards found. Try a different delimiter or check the format guide." : nil
                                isParsing = false
                            }
                        }
                    }
                }
            }
            .onChange(of: delimiter) { _, _ in
                if importedFileName == nil {
                    let trimmed = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return } // don't re-parse if it's JSON
                    
                    parseTask?.cancel()
                    parseTask = Task {
                        await MainActor.run { isParsing = true }
                        let d = delimiter.character
                        let text = pastedText
                        let specs = await Task.detached { Self.parseCSV(text, delimiter: d) }.value
                        if Task.isCancelled { return }
                        await MainActor.run {
                            parsedSpecs = specs
                            isParsing = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var importContent: some View {
        Group {
            Section {
                Button {
                    showFilePicker = true
                } label: {
                    Label(importedFileName ?? "Choose .json / .csv / .txt file", systemImage: "doc.badge.plus")
                }
                
                // Only show delimiter picker if a text file is loaded or JSON isn't detected
                if !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") &&
                   !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                    Picker("Delimiter (CSV/TXT)", selection: $delimiter) {
                        ForEach(Delimiter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
            } header: {
                Text("Source File")
            } footer: {
                Button("View required formats & examples") {
                    showFormatGuide = true
                }
            }

            if importedFileName == nil {
                Section {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 200)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Or paste text directly")
                } footer: {
                    Text("Auto-detects JSON or delimited text. Tap **?** in the toolbar for formats.")
                }
            } else {
                Section {
                    Button("Clear file") {
                        importedFileName = nil
                        parsedSpecs = []
                        pastedText = ""
                        parseError = nil
                    }
                    .foregroundStyle(Theme.destructive)
                }
            }

            if let err = parseError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.destructive)
                        .font(.caption)
                }
            }

            if !parsedSpecs.isEmpty {
                previewSection(parsedSpecs)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private func previewSection(_ specs: [CardSpec]) -> some View {
        let mcqCount = specs.filter(\.hasMCQOptions).count
        Section {
            if specs.isEmpty {
                Text("No valid cards found — check the format.")
                    .foregroundStyle(.secondary)
            } else {
                if mcqCount > 0 {
                    Label("\(mcqCount) of \(specs.count) cards have MCQ options stored",
                          systemImage: "list.bullet.rectangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(specs.prefix(5).enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.front).fontWeight(.medium).lineLimit(2)
                        Text(s.back).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if s.hasMCQOptions {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.square.fill")
                                    .font(.caption2).foregroundStyle(Theme.success)
                                Text("\(s.optionCount) wrong option\(s.optionCount == 1 ? "" : "s") stored")
                                    .font(.caption2).foregroundStyle(Theme.success)
                            }
                        }
                    }
                }
                if specs.count > 5 {
                    Text("…and \(specs.count - 5) more")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Preview (\(specs.count) cards)")
        }
    }

    // MARK: - File handling

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            
            pastedText = "" // Never put massive file contents into TextEditor
            parseError = nil
            isParsing = true
            
            if urls.count == 1 {
                importedFileName = urls[0].lastPathComponent
            } else {
                importedFileName = "\(urls.count) files selected"
            }
            
            Task.detached {
                var allSpecs: [CardSpec] = []
                var allUnmapped: [[String: Any]] = []
                var errors: [String] = []
                
                for url in urls {
                    let needsScope = url.startAccessingSecurityScopedResource()
                    
                    do {
                        let data = try Data(contentsOf: url)
                        let ext = url.pathExtension.lowercased()
                        let s = String(data: data, encoding: .utf8) ?? ""
                        let isLikelyJson = ext == "json" || s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") || s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
                        
                        if isLikelyJson {
                            let specs = try BulkImportView.parseJSONData(data)
                            if specs.isEmpty {
                                let flatObjs = BulkImportView.extractFlatObjects(from: data)
                                if !flatObjs.isEmpty {
                                    allUnmapped.append(contentsOf: flatObjs)
                                }
                            } else {
                                allSpecs.append(contentsOf: specs)
                            }
                        } else {
                            let d: String = await MainActor.run {
                                if ext == "csv" { return "," }
                                if ext == "tsv" { return "\t" }
                                return self.delimiter.character
                            }
                            let textToParse = s.isEmpty ? (String(data: data, encoding: .isoLatin1) ?? "") : s
                            let specs = BulkImportView.parseCSV(textToParse, delimiter: d)
                            if specs.isEmpty && BulkImportView.looksLikeMCQ(textToParse) {
                                let blocks = BulkImportView.parseTextMCQ(textToParse)
                                // Separate already-answered blocks from ones needing picker
                                let complete = blocks.filter(\.isComplete)
                                let incomplete = blocks.filter { !$0.isComplete }
                                allSpecs.append(contentsOf: complete.compactMap { $0.toCardSpec() })
                                if !incomplete.isEmpty {
                                    await MainActor.run { self.pendingMCQBlocks.append(contentsOf: incomplete) }
                                }
                            } else {
                                allSpecs.append(contentsOf: specs)
                            }
                        }
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                    if needsScope { url.stopAccessingSecurityScopedResource() }
                }
                let finalSpecs = allSpecs
                let finalUnmapped = allUnmapped
                let finalErrors = errors
                
                let hasPendingBlocks = await MainActor.run { !self.pendingMCQBlocks.isEmpty }
                await MainActor.run {
                    self.parsedSpecs = finalSpecs
                    if !finalUnmapped.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.unmappedJSONObjects = finalUnmapped
                        }
                    } else if hasPendingBlocks {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.showMCQAnswerPicker = true
                        }
                    } else if finalSpecs.isEmpty {
                        self.parseError = finalErrors.isEmpty ? "No valid cards found in any file." : finalErrors.joined(separator: "\n")
                    } else if !finalErrors.isEmpty {
                        self.parseError = "Parsed \(finalSpecs.count) cards, but had errors:\n" + finalErrors.joined(separator: "\n")
                    }
                    self.isParsing = false
                }
            }
        case .failure(let e):
            resultMessage = "Pick failed: \(e.localizedDescription)"
        }
    }

    // MARK: - Import

    private func runImport() {
        let specs = parsedSpecs
        guard !specs.isEmpty else { return }
        isImporting = true
        
        // 1. Build a set of existing fronts to prevent duplicates
        let existingFronts = Set(deck.cards.map { $0.front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        
        var uniqueSpecs: [CardSpec] = []
        var seenFronts = existingFronts
        var duplicateCount = 0
        
        for s in specs {
            let key = s.front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if seenFronts.contains(key) {
                duplicateCount += 1
            } else {
                seenFronts.insert(key)
                uniqueSpecs.append(s)
            }
        }
        
        Task {
            defer { isImporting = false }
            for (i, s) in uniqueSpecs.enumerated() {
                let card = Card(front: s.front, back: s.back, deck: deck)
                card.option1 = s.option1
                card.option2 = s.option2
                card.option3 = s.option3
                card.storedExplanation = s.explanation
                ctx.insert(card)
                
                // Save and yield every 1000 cards so the UI stays responsive
                if i % 1000 == 0 {
                    try? ctx.save()
                    await Task.yield()
                }
            }
            do {
                try ctx.save()
            } catch {
                resultMessage = "Import failed — could not save: \(error.localizedDescription)"
                return
            }
            let mcq = uniqueSpecs.filter(\.hasMCQOptions).count
            var msg = "Added \(uniqueSpecs.count) card\(uniqueSpecs.count == 1 ? "" : "s") to \(deck.name)."
            if mcq > 0 { msg += " \(mcq) have MCQ options." }
            if duplicateCount > 0 { msg += " (Skipped \(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s"))." }
            resultMessage = msg
        }
    }

    // MARK: - JSON parsing

    // Inlined into background tasks to prevent main thread freezing

    /// Parses multiple JSON shapes into CardSpec array.
    nonisolated static func parseJSONData(_ data: Data) throws -> [CardSpec] {
        let obj = try JSONSerialization.jsonObject(with: data)

        if let arr = obj as? [[String: Any]] {
            return arr.compactMap { parseSingleCard($0) }
        }

        if let dict = obj as? [String: Any] {
            // Full backup: {"decks": [{"cards": [...]}]}
            if let decksArr = dict["decks"] as? [[String: Any]] {
                return decksArr.flatMap { deckDict -> [CardSpec] in
                    guard let cardsArr = deckDict["cards"] as? [[String: Any]] else { return [] }
                    return cardsArr.compactMap { parseSingleCard($0) }
                }
            }
            // Wrapper: {"cards": [...]} or {"questions": [...]}
            for key in ["cards", "questions", "data", "items", "flashcards"] {
                if let arr = dict[key] as? [[String: Any]] {
                    return arr.compactMap { parseSingleCard($0) }
                }
            }
            // Single card
            if let spec = parseSingleCard(dict) { return [spec] }
        }

        return []
    }

    nonisolated static func extractFlatObjects(from data: Data) -> [[String: Any]] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = obj as? [[String: Any]] { return arr }
        if let dict = obj as? [String: Any] {
            if let arr = dict["decks"] as? [[String: Any]] {
                return arr.flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }
            }
            if let arr = dict["cards"] as? [[String: Any]] {
                return arr
            }
            for value in dict.values {
                if let arr = value as? [[String: Any]], !arr.isEmpty {
                    return arr
                }
            }
        }
        return []
    }

    nonisolated static func extractEmbeddedOptions(front: String, back: String) -> CardSpec? {
        guard front.contains("(A)") else { return nil }

        guard let aRange = front.range(of: "(A)") else { return nil }
        let questionText = String(front[..<aRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

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
            var text = String(front[textStart..<textEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                
            if let markerIndex = text.firstIndex(of: "■") {
                text = String(text[..<markerIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
                
            optionsByLetter[letter] = text
        }

        guard optionsByLetter.count == 4 else { return nil }
        let allOptions = ["A","B","C","D"].compactMap { optionsByLetter[$0.first!] }
        guard allOptions.count == 4 else { return nil }

        let b = back.trimmingCharacters(in: .whitespaces)
        let correctLetter: Character?
        if b.hasPrefix("("), b.count >= 2 {
            correctLetter = b[b.index(after: b.startIndex)]
        } else if let first = b.first, "ABCD".contains(first) {
            correctLetter = first
        } else {
            correctLetter = nil
        }

        guard let cl = correctLetter, let correctText = optionsByLetter[cl] else { return nil }
        
        let wrongs = allOptions.filter { $0 != correctText }
        guard wrongs.count >= 3 else { return nil }
        
        let expl = back.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CardSpec(
            front: questionText,
            back: correctText,          // store the actual answer text, not "(A)" etc.
            option1: wrongs[0],
            option2: wrongs[1],
            option3: wrongs[2],
            explanation: expl.isEmpty ? nil : expl
        )
    }

    // MARK: - Single-card parser (handles all formats)

    nonisolated static func parseSingleCard(_ d: [String: Any]) -> CardSpec? {
        let str = { (key: String) -> String in
            (d[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        // ── Format A: explicit option1/2/3 fields (from our AI generator or manual) ──
        let frontA = str("front").ne ?? str("term").ne ?? str("question").ne ?? str("q").ne ?? str("stem").ne
        let backA  = str("back").ne  ?? str("definition").ne
        if let f = frontA, let b = backA {
            if let extracted = extractEmbeddedOptions(front: f, back: b) {
                return extracted
            }
            return CardSpec(
                front: f, back: b,
                option1: str("option1").ne,
                option2: str("option2").ne,
                option3: str("option3").ne,
                explanation: str("explanation").ne ?? str("rationale").ne
            )
        }

        // ── Format B: {question/stem, options:[], answer/correct_letter} ──
        let questionB = str("question").ne ?? str("front").ne ?? str("q").ne ?? str("stem").ne ?? str("title").ne
        let answerRaw = str("answer").ne ?? str("correct_answer").ne ?? str("correctAnswer").ne
                        ?? str("correct").ne ?? str("correct_option").ne ?? str("correct_letter").ne

        // Normalize options to [String] + capture is_correct index from dict-array options
        var optionsArray: [String]? = d["options"] as? [String]
        var explicitCorrectIdx: Int? = nil  // set when options carry is_correct flags

        if optionsArray == nil, let dictArray = d["options"] as? [[String: Any]], !dictArray.isEmpty {
            // {"option_text": "...", "is_correct": true/false} — static_gk format
            var texts: [String] = []
            for (i, dict) in dictArray.enumerated() {
                let text = (dict["option_text"] as? String)
                    ?? (dict["text"] as? String)
                    ?? dict.values.compactMap { $0 as? String }.first ?? ""
                texts.append(text)
                if let isCorrect = dict["is_correct"] as? Bool, isCorrect { explicitCorrectIdx = i }
            }
            if !texts.isEmpty { optionsArray = texts }
        }

        if optionsArray == nil, let raw = (d["options"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if raw.contains("\n") {
                optionsArray = raw.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else if raw.range(of: #"[A-Da-d][.)]\s"#, options: .regularExpression) != nil {
                optionsArray = raw.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        }

        if let question = questionB, let options = optionsArray, !options.isEmpty {
            let cleaned = options.map { stripOptionPrefix($0) }

            // Priority: explicit is_correct > letter marker > full-text match
            let correctIdx: Int?
            if let explicit = explicitCorrectIdx {
                correctIdx = explicit
            } else if let ans = answerRaw {
                let isJustMarker = ans.range(of: #"^\s*[\(\[]?([A-Da-d])[\)\]\.:)]?\s*$"#, options: .regularExpression) != nil
                if isJustMarker, let letterChar = ans.first(where: { "ABCDabcd".contains($0) }) {
                    correctIdx = ["A","B","C","D"].firstIndex(of: String(letterChar).uppercased())
                } else {
                    let ansLower = ans.lowercased()
                    let ansStripped = stripOptionPrefix(ans).lowercased()
                    correctIdx = cleaned.indices.first {
                        cleaned[$0].lowercased() == ansLower ||
                        (ansStripped != ansLower && cleaned[$0].lowercased() == ansStripped) ||
                        options[$0].lowercased() == ansLower ||
                        options[$0].lowercased().hasSuffix(ansLower)
                    }
                }
            } else {
                correctIdx = nil
            }

            let idx = correctIdx ?? 0
            let back = cleaned[idx]
            let wrongs = cleaned.indices.filter { $0 != idx }.map { cleaned[$0] }
            let expl = str("explanation").ne ?? str("rationale").ne
            return CardSpec(
                front: question,
                back: back,
                option1: wrongs.count > 0 ? wrongs[0] : nil,
                option2: wrongs.count > 1 ? wrongs[1] : nil,
                option3: wrongs.count > 2 ? wrongs[2] : nil,
                explanation: expl
            )
        }

        // ── Format C: plain {question/front, answer} — no options array ──
        if let question = questionB, let answer = answerRaw {
            let expl = str("explanation").ne ?? str("rationale").ne
            return CardSpec(front: question, back: answer, explanation: expl)
        }

        return nil
    }

    nonisolated static func stripOptionPrefix(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        // Match 1: (A) or [A], optionally followed by . or : and spaces
        // Match 2: A. or A) or A: followed by spaces
        let pattern = #"^([\(\[][A-Da-d][\)\]][\.:]?|[A-Da-d][\)\]\.:])\s*"#
        if let range = t.range(of: pattern, options: .regularExpression) {
            let stripped = String(t[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty ? t : stripped
        }
        return t
    }

    // MARK: - CSV parsing (updated: supports up to 5 columns)

    nonisolated static func parseCSV(_ text: String, delimiter: String) -> [CardSpec] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        var out: [CardSpec] = []
        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts: [String]
            if delimiter == "," {
                parts = splitCSVLine(line)
            } else {
                parts = line.components(separatedBy: delimiter).map(stripQuotes)
            }
            guard parts.count >= 2 else { continue }

            let front = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back  = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            
            // Automatically ignore header rows (Flashcards World format)
            if front.lowercased() == "front" || front.lowercased() == "question" {
                if back.lowercased() == "back" || back.lowercased() == "answer" {
                    continue
                }
            }

            let o1 = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines).ne : nil
            let o2 = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespacesAndNewlines).ne : nil
            let o3 = parts.count > 4 ? parts[4].trimmingCharacters(in: .whitespacesAndNewlines).ne : nil

            out.append(CardSpec(front: front, back: back, option1: o1, option2: o2, option3: o3))
        }
        return out
    }

    nonisolated private static func stripQuotes(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
            t = String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
        }
        return t
    }

    nonisolated private static func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                if inQuotes {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else { inQuotes = false }
                } else { inQuotes = true }
            } else if c == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else { current.append(c) }
            i = line.index(after: i)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}

private extension String {
    /// nil if empty, self otherwise.
    var ne: String? { isEmpty ? nil : self }
}

// MARK: - Raw MCQ Block (plain-text / PDF MCQ parsing)

struct MCQOption: Identifiable {
    let id = UUID()
    let letter: String
    let text: String
}

struct RawMCQBlock: Identifiable {
    let id = UUID()
    var number: Int?
    var question: String
    var options: [MCQOption]
    var answer: String?         // "A" / "B" / "C" / "D"
    var explanation: String?

    var isComplete: Bool { answer != nil && !options.isEmpty }

    func toCardSpec() -> CardSpec? {
        guard !question.isEmpty, !options.isEmpty else { return nil }
        let ans = answer ?? options.first?.letter ?? "A"
        let correct = options.first(where: { $0.letter == ans })?.text ?? options[0].text
        let wrongs = options.filter { $0.letter != ans }.map(\.text)
        return CardSpec(
            front: question,
            back: correct,
            option1: wrongs.count > 0 ? wrongs[0] : nil,
            option2: wrongs.count > 1 ? wrongs[1] : nil,
            option3: wrongs.count > 2 ? wrongs[2] : nil,
            explanation: explanation
        )
    }
}

// MARK: - Text MCQ Parser

extension BulkImportView {

    /// Called on the main actor to route MCQ blocks into direct specs or the answer picker.
    nonisolated static func applyMCQBlocks(
        _ blocks: [RawMCQBlock],
        to specs: inout [CardSpec],
        pending: inout [RawMCQBlock],
        show: inout Bool,
        error: inout String?
    ) {
        guard !blocks.isEmpty else {
            error = "No MCQ questions detected. Check the format guide."
            return
        }
        let complete   = blocks.filter(\.isComplete)
        let incomplete = blocks.filter { !$0.isComplete }
        specs = complete.compactMap { $0.toCardSpec() }
        if !incomplete.isEmpty {
            pending = incomplete
            show = true
        } else {
            error = nil
        }
    }

    nonisolated static func looksLikeMCQ(_ text: String) -> Bool {
        let sample = String(text.prefix(4000))
        guard let re = try? NSRegularExpression(pattern: #"(?m)^[\(\[]?[A-Da-d][\)\].:]\s"#) else { return false }
        return re.numberOfMatches(in: sample, range: NSRange(sample.startIndex..., in: sample)) >= 4
    }

    /// Parses plain-text MCQ documents into RawMCQBlock array.
    /// Handles inline answers, end-of-document answer keys, and missing answers.
    nonisolated static func parseTextMCQ(_ text: String) -> [RawMCQBlock] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        let qRe   = try? NSRegularExpression(pattern: #"^(?:Q\.?\s*)?(\d+)[.)]\s+(\S.*)"#)
        let optRe = try? NSRegularExpression(pattern: #"^[\(\[]?([A-Da-d])[\)\].:]\s+(.*)"#)
        let ansRe = try? NSRegularExpression(pattern: #"(?i)^(?:ans(?:wer)?s?|correct(?:\s+ans(?:wer)?)?|solution)[.:]\s*[\(\[]?([A-Da-d])[\)\].]?"#)
        let keyHdrRe = try? NSRegularExpression(pattern: #"(?i)^(?:answers?|answer\s+key|solutions?|ans\s+key)\s*:?\s*$"#)

        var blocks: [RawMCQBlock] = []
        var qNum: Int? = nil
        var qLines: [String] = []
        var opts: [(String, String)] = []
        var answer: String? = nil
        var explLines: [String] = []
        var inOptions = false
        var inAnswerKey = false
        var answerKeyLines: [String] = []

        func commit() {
            guard !qLines.isEmpty else { return }
            let q = qLines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty, !opts.isEmpty else { qLines = []; opts = []; answer = nil; explLines = []; inOptions = false; return }
            let expl = explLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            blocks.append(RawMCQBlock(
                number: qNum,
                question: q,
                options: opts.map { MCQOption(letter: $0.0, text: $0.1) },
                answer: answer,
                explanation: expl.isEmpty ? nil : expl
            ))
            qNum = nil; qLines = []; opts = []; answer = nil; explLines = []; inOptions = false
        }

        func match(_ re: NSRegularExpression?, _ s: String) -> NSTextCheckingResult? {
            guard let re else { return nil }
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        }

        func group(_ m: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
            guard m.numberOfRanges > i, let r = Range(m.range(at: i), in: s) else { return nil }
            return String(s[r])
        }

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Answer-key section header
            if match(keyHdrRe, t) != nil { commit(); inAnswerKey = true; continue }
            if inAnswerKey { if !t.isEmpty { answerKeyLines.append(t) }; continue }

            // New question start
            if let m = match(qRe, t) {
                commit()
                qNum = group(m, 1, in: t).flatMap(Int.init)
                qLines = [group(m, 2, in: t) ?? ""].filter { !$0.isEmpty }
                continue
            }

            // Guard: only parse options/answers when we're inside a question block
            guard !qLines.isEmpty else { continue }

            // Option line
            if let m = match(optRe, t), answer == nil {
                inOptions = true
                let letter = (group(m, 1, in: t) ?? "?").uppercased()
                let text   = (group(m, 2, in: t) ?? "").trimmingCharacters(in: .whitespaces)
                opts.append((letter, text))
                continue
            }

            // Inline answer line
            if let m = match(ansRe, t) {
                if let letter = group(m, 1, in: t)?.uppercased() { answer = letter }
                continue
            }

            // Remaining text
            if t.isEmpty { continue }
            if answer != nil {
                explLines.append(t)
            } else if inOptions, !opts.isEmpty {
                // Continuation of last option text
                opts[opts.count - 1].1 += " " + t
            } else if !inOptions {
                qLines.append(t)
            }
        }
        commit()

        // --- Apply end-of-document answer key ---
        if !answerKeyLines.isEmpty {
            var ansMap: [Int: String] = [:]
            let combined = answerKeyLines.joined(separator: " ")
            // Format: "1. A  2. B  3. C" or "1-A, 2-B"
            if let re = try? NSRegularExpression(pattern: #"(\d+)[.):\s\-]+[\(\[]?([A-Da-d])[\)\].]?"#) {
                for m in re.matches(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
                    if let nr = Range(m.range(at: 1), in: combined),
                       let lr = Range(m.range(at: 2), in: combined),
                       let n = Int(String(combined[nr])) {
                        ansMap[n] = String(combined[lr]).uppercased()
                    }
                }
            }
            // Fallback: one answer per line (line index = question number)
            if ansMap.isEmpty {
                for (i, ln) in answerKeyLines.enumerated() {
                    if let r = ln.range(of: #"[\(\[]?([A-Da-d])[\)\].]?"#, options: .regularExpression) {
                        let letter = String(ln[r]).filter { "ABCDabcd".contains($0) }.uppercased()
                        if !letter.isEmpty { ansMap[i + 1] = letter }
                    }
                }
            }
            for i in blocks.indices where blocks[i].answer == nil {
                if let n = blocks[i].number, let a = ansMap[n] { blocks[i].answer = a }
            }
        }

        return blocks.filter { !$0.options.isEmpty && !$0.question.isEmpty }
    }
}

import SwiftUI

struct JSONMappingView: View {
    let unmappedObjects: [[String: Any]]
    let onMapped: ([CardSpec]) -> Void
    let onCancel: () -> Void

    @State private var availableKeys: [String] = []
    
    @State private var frontKey: String = ""
    @State private var backKey: String = ""
    @State private var explanationKey: String = ""
    @State private var optionsKey: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("We found \(unmappedObjects.count) objects, but couldn't auto-detect the question and answer fields. Please map them below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Required Fields") {
                    Picker("Front / Question", selection: $frontKey) {
                        Text("Not selected").tag("")
                        ForEach(availableKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                    Picker("Back / Answer", selection: $backKey) {
                        Text("Not selected").tag("")
                        ForEach(availableKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                }
                
                Section("Optional Fields") {
                    Picker("Explanation", selection: $explanationKey) {
                        Text("None").tag("")
                        ForEach(availableKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                    Picker("Options Array (for MCQ)", selection: $optionsKey) {
                        Text("None").tag("")
                        ForEach(availableKeys, id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                }
                
                Section {
                    Button("Import Cards") {
                        processMapping()
                    }
                    .disabled(frontKey.isEmpty || backKey.isEmpty)
                }
            }
            .navigationTitle("Map JSON Fields")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .onAppear(perform: extractKeys)
        }
    }
    
    private func extractKeys() {
        var keySet = Set<String>()
        // Just sample the first few objects to find keys
        for obj in unmappedObjects.prefix(50) {
            for k in obj.keys {
                keySet.insert(k)
            }
        }
        availableKeys = Array(keySet).sorted()
        
        // Auto-select likely matches
        let frontSynonyms = ["stem", "question", "front", "term", "q", "title", "prompt"]
        let backSynonyms = ["correct_letter", "answer", "back", "definition", "a", "correct_answer", "correctanswer", "correct"]
        let explSynonyms = ["explanation", "rationale", "reasoning", "info", "notes", "description"]
        let optSynonyms = ["options", "choices", "alternatives", "answers"]
        
        for key in availableKeys {
            let lowerKey = key.lowercased()
            if frontKey.isEmpty && frontSynonyms.contains(where: { lowerKey.contains($0) }) {
                frontKey = key
            }
            if backKey.isEmpty && backSynonyms.contains(where: { lowerKey.contains($0) }) {
                backKey = key
            }
            if explanationKey.isEmpty && explSynonyms.contains(where: { lowerKey.contains($0) }) {
                explanationKey = key
            }
            if optionsKey.isEmpty && optSynonyms.contains(where: { lowerKey.contains($0) }) {
                optionsKey = key
            }
        }
    }
    
    private func processMapping() {
        var specs: [CardSpec] = []
        for obj in unmappedObjects {
            let front = (obj[frontKey] as? String) ?? ""
            var back = (obj[backKey] as? String) ?? ""
            
            // If the back is an integer or number in the JSON (e.g. index for the correct option), we should handle that gracefully if it's an option index
            // But standard string fallback first:
            if back.isEmpty, let bInt = obj[backKey] as? Int {
                back = String(bInt)
            }
            
            guard !front.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            
            let expl = explanationKey.isEmpty ? nil : (obj[explanationKey] as? String)
            
            var spec = CardSpec(front: front, back: back, explanation: expl)
            
            if !optionsKey.isEmpty {
                var cleanedOpts: [String] = []
                var explicitCorrectIdx: Int? = nil
                
                if let optsArray = obj[optionsKey] as? [String] {
                    cleanedOpts = optsArray.map { BulkImportView.stripOptionPrefix($0) }
                } else if let dictArray = obj[optionsKey] as? [[String: Any]] {
                    for (i, dict) in dictArray.enumerated() {
                        let text = (dict["option_text"] as? String) ?? (dict["text"] as? String) ?? dict.values.compactMap { $0 as? String }.first ?? ""
                        cleanedOpts.append(BulkImportView.stripOptionPrefix(text))
                        
                        if let isCorrect = dict["is_correct"] as? Bool, isCorrect {
                            explicitCorrectIdx = i
                        }
                    }
                }
                
                if !cleanedOpts.isEmpty {
                    let correctIdx: Int?
                    if let explicit = explicitCorrectIdx {
                        correctIdx = explicit
                    } else if let idx = Int(back), idx >= 0, idx < cleanedOpts.count {
                        correctIdx = idx
                    } else if back.count == 1, let letterIdx = ["A","B","C","D","E"].firstIndex(of: back.uppercased()), letterIdx < cleanedOpts.count {
                        correctIdx = letterIdx
                    } else {
                        let ansLower = back.lowercased()
                        correctIdx = cleanedOpts.indices.first {
                            cleanedOpts[$0].lowercased() == ansLower ||
                            cleanedOpts[$0].lowercased().hasSuffix(ansLower)
                        }
                    }
                    
                    let idx = correctIdx ?? 0
                    spec.back = cleanedOpts.indices.contains(idx) ? cleanedOpts[idx] : back
                    let wrongs = cleanedOpts.indices.filter { $0 != idx }.map { cleanedOpts[$0] }
                    
                    if wrongs.count > 0 { spec.option1 = wrongs[0] }
                    if wrongs.count > 1 { spec.option2 = wrongs[1] }
                    if wrongs.count > 2 { spec.option3 = wrongs[2] }
                }
            }
            
            specs.append(spec)
        }
        onMapped(specs)
    }
}
