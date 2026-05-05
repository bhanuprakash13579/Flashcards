import SwiftUI
import SwiftData

// MARK: - Library browser

struct LibraryView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss)      private var dismiss

    @State private var subjects:    [LibrarySubject] = []
    @State private var expanded:    Set<String>      = []
    @State private var selected:    Set<String>      = []   // chapter deckIds
    @State private var importing    = false
    @State private var importResult: String?
    @State private var showResult   = false

    var body: some View {
        NavigationStack {
            Group {
                if subjects.isEmpty {
                    ContentUnavailableView("Library unavailable",
                        systemImage: "books.vertical",
                        description: Text("No bundled flashcard sets found."))
                } else {
                    list
                }
            }
            .navigationTitle("Flashcard Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    importButton
                }
            }
            .alert("Import complete", isPresented: $showResult) {
                Button("OK") { if importResult != nil { dismiss() } }
            } message: {
                Text(importResult ?? "")
            }
        }
        .onAppear {
            subjects = LibraryService.loadManifest()
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            selectionSummaryHeader
            ForEach(subjects) { subject in
                subjectSection(subject)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var selectionSummaryHeader: some View {
        let chapterCount = selected.count
        let cardCount    = cardCountForSelection()
        if chapterCount > 0 {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(chapterCount) chapter\(chapterCount == 1 ? "" : "s") selected")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("\(cardCount) cards will be added to your library")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear") { selected.removeAll() }
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func subjectSection(_ subject: LibrarySubject) -> some View {
        let isExpanded = expanded.contains(subject.id)
        let selectedCount = subject.chapters.filter { selected.contains($0.deckId) }.count

        Section {
            // Subject header row
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    if isExpanded { expanded.remove(subject.id) }
                    else          { expanded.insert(subject.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: subject.colorHex).opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: subject.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: subject.colorHex))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subject.name).font(.headline).foregroundStyle(.primary)
                        Text("\(subject.cardCount) cards · \(subject.chapters.count) chapters")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color(hex: subject.colorHex), in: Capsule())
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Select-all row
                Button {
                    let allIds = Set(subject.chapters.map(\.deckId))
                    if allIds.isSubset(of: selected) {
                        selected.subtract(allIds)
                    } else {
                        selected.formUnion(allIds)
                    }
                } label: {
                    let allSelected = subject.chapters.allSatisfy { selected.contains($0.deckId) }
                    Label(
                        allSelected ? "Deselect all chapters" : "Select all chapters",
                        systemImage: allSelected ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Color(hex: subject.colorHex))
                }
                .buttonStyle(.plain)
                .padding(.leading, 52)

                ForEach(subject.chapters) { chapter in
                    chapterRow(chapter, subject: subject)
                }
            }
        }
    }

    private func chapterRow(_ chapter: LibraryChapter, subject: LibrarySubject) -> some View {
        let isSelected = selected.contains(chapter.deckId)
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                if isSelected { selected.remove(chapter.deckId) }
                else          { selected.insert(chapter.deckId) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color(hex: subject.colorHex) : .secondary)
                    .animation(.easeOut(duration: 0.12), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.name)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("\(chapter.cardCount) cards")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.leading, 40)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import button

    @ViewBuilder
    private var importButton: some View {
        if selected.isEmpty {
            EmptyView()
        } else {
            Button {
                doImport()
            } label: {
                if importing {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    Text("Add (\(selected.count))")
                        .fontWeight(.semibold)
                }
            }
            .disabled(importing)
        }
    }

    // MARK: - Logic

    private func doImport() {
        importing = true
        var totalDecks = 0
        var totalCards = 0

        // Group selected chapters by subject
        var bySubject: [String: (filename: String, name: String, deckIds: Set<String>)] = [:]
        for subject in subjects {
            for chapter in subject.chapters where selected.contains(chapter.deckId) {
                var entry = bySubject[subject.id] ?? (subject.filename, subject.name, [])
                entry.deckIds.insert(chapter.deckId)
                bySubject[subject.id] = entry
            }
        }

        do {
            for (_, info) in bySubject {
                let (d, c) = try LibraryService.importChapters(
                    subjectFilename: info.filename,
                    selectedDeckIds: info.deckIds,
                    parentSubjectName: info.name,
                    into: ctx
                )
                totalDecks += d
                totalCards += c
            }
            if totalCards == 0 {
                importResult = "Already up to date — no new cards to add."
            } else if totalDecks == 0 {
                importResult = "\(totalCards) new card\(totalCards == 1 ? "" : "s") added to existing decks."
            } else {
                importResult = "\(totalDecks) deck\(totalDecks == 1 ? "" : "s") and \(totalCards) card\(totalCards == 1 ? "" : "s") added to your library."
            }
        } catch {
            importResult = "Import failed: \(error.localizedDescription)"
        }

        importing  = false
        showResult = true
    }

    private func cardCountForSelection() -> Int {
        var count = 0
        for subject in subjects {
            for chapter in subject.chapters where selected.contains(chapter.deckId) {
                count += chapter.cardCount
            }
        }
        return count
    }
}
