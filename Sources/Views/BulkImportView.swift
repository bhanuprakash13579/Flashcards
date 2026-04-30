import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BulkImportView: View {
    let deck: Deck
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable, Identifiable {
        case paste = "Paste text"
        case file  = "Pick file"
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

    @State private var source: Source = .paste
    @State private var pastedText: String = ""
    @State private var delimiter: Delimiter = .tab
    @State private var fileImporting = false
    @State private var importedFileName: String?
    @State private var resultMessage: String?

    private var parsed: [(front: String, back: String)] {
        Self.parse(pastedText, delimiter: delimiter.character)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    Picker("From", selection: $source) {
                        ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if source == .file {
                        Button {
                            fileImporting = true
                        } label: {
                            Label(importedFileName ?? "Choose .csv / .tsv / .txt", systemImage: "doc")
                        }
                    }
                }

                Section("Format") {
                    Picker("Delimiter", selection: $delimiter) {
                        ForEach(Delimiter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 180)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("Lines")
                } footer: {
                    Text("One card per line, **front\(delimiter == .tab ? "↹" : delimiter.character)back**. Empty lines and lines starting with `#` are ignored. Surrounding double quotes are stripped.")
                }

                if !pastedText.isEmpty {
                    Section("Preview (\(parsed.count) cards)") {
                        if parsed.isEmpty {
                            Text("No valid lines yet — check the delimiter.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(parsed.prefix(5).enumerated()), id: \.offset) { _, p in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.front).fontWeight(.medium).lineLimit(1)
                                    Text(p.back).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            if parsed.count > 5 {
                                Text("…and \(parsed.count - 5) more").font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bulk import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(parsed.count)") { runImport() }
                        .disabled(parsed.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $fileImporting,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handlePickedFile(result)
            }
            .alert("Done", isPresented: .constant(resultMessage != nil), presenting: resultMessage) { _ in
                Button("OK") {
                    resultMessage = nil
                    dismiss()
                }
            } message: { msg in Text(msg) }
        }
    }

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if let s = String(data: data, encoding: .utf8) {
                    pastedText = s
                } else if let s = String(data: data, encoding: .isoLatin1) {
                    pastedText = s
                }
                importedFileName = url.lastPathComponent
                if url.pathExtension.lowercased() == "csv" { delimiter = .comma }
                if url.pathExtension.lowercased() == "tsv" { delimiter = .tab }
            } catch {
                resultMessage = "Could not read file: \(error.localizedDescription)"
            }
        case .failure(let e):
            resultMessage = "Pick failed: \(e.localizedDescription)"
        }
    }

    private func runImport() {
        let pairs = parsed
        guard !pairs.isEmpty else { return }
        for p in pairs {
            let card = Card(front: p.front, back: p.back, deck: deck)
            ctx.insert(card)
        }
        try? ctx.save()
        resultMessage = "Added \(pairs.count) card\(pairs.count == 1 ? "" : "s") to \(deck.name)."
    }

    /// Lightweight parser. Handles basic CSV-style quoting (\"foo, bar\") for single delimiters.
    static func parse(_ text: String, delimiter: String) -> [(front: String, back: String)] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        var out: [(String, String)] = []
        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts: [String]
            if delimiter == "," {
                parts = splitCSVLine(line)
            } else {
                let split = line.components(separatedBy: delimiter)
                parts = split.map(stripQuotes)
            }
            guard parts.count >= 2 else { continue }
            let front = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = parts[1...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !front.isEmpty && !back.isEmpty {
                out.append((front, back))
            }
        }
        return out
    }

    private static func stripQuotes(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
            t = String(t.dropFirst().dropLast()).replacingOccurrences(of: "\"\"", with: "\"")
        }
        return t
    }

    /// Minimal CSV line splitter that respects double-quoted fields.
    private static func splitCSVLine(_ line: String) -> [String] {
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
                    } else {
                        inQuotes = false
                    }
                } else {
                    inQuotes = true
                }
            } else if c == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}
