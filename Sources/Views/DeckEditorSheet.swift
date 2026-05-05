import SwiftUI
import SwiftData

struct DeckEditorSheet: View {
    /// Pass nil to create a new deck; pass an existing deck to edit it.
    var deck: Deck?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]

    @State private var name = ""
    @State private var colorHex = DeckPalette.random()
    @State private var selectedTags: Set<UUID> = []
    @State private var newTagName = ""
    @State private var newTagColor = DeckPalette.colors[4]
    @State private var showAddTag = false

    private var isEditing: Bool { deck != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                colorSection
                tagSection
            }
            .navigationTitle(isEditing ? "Edit deck" : "New deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { loadInitial() }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Deck name", text: $name)
        }
    }

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 10) {
                ForEach(DeckPalette.colors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.primary, lineWidth: colorHex == hex ? 2.5 : 0)
                                .padding(2)
                        )
                        .onTapGesture { colorHex = hex }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var tagSection: some View {
        Section {
            if allTags.isEmpty && !showAddTag {
                Text("No tags yet — create one to group your decks.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(allTags, id: \.id) { (tag: Tag) in
                HStack {
                    Circle()
                        .fill(Color(hex: tag.colorHex))
                        .frame(width: 10, height: 10)
                    Text(tag.name)
                    Spacer()
                    if selectedTags.contains(tag.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedTags.contains(tag.id) {
                        selectedTags.remove(tag.id)
                    } else {
                        selectedTags.insert(tag.id)
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { ctx.delete(allTags[i]) }
                try? ctx.save()
            }

            if showAddTag {
                addTagRow
            } else {
                Button {
                    showAddTag = true
                } label: {
                    Label("New tag", systemImage: "plus")
                }
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Tags let you group decks by subject (e.g. Polity, Economics). Swipe to delete a tag.")
        }
    }

    private var addTagRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Tag name", text: $newTagName)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DeckPalette.colors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: newTagColor == hex ? 2 : 0)
                                    .padding(2)
                            )
                            .onTapGesture { newTagColor = hex }
                    }
                }
            }
            HStack {
                Button("Cancel") {
                    newTagName = ""
                    showAddTag = false
                }
                Spacer()
                Button("Add tag") {
                    let n = newTagName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    let tag = Tag(name: n, colorHex: newTagColor)
                    ctx.insert(tag)
                    try? ctx.save()
                    selectedTags.insert(tag.id)
                    newTagName = ""
                    showAddTag = false
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                .fontWeight(.semibold)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func loadInitial() {
        if let deck {
            name = deck.name
            colorHex = deck.colorHex
            selectedTags = Set(deck.tags.map(\.id))
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let pickedTags = allTags.filter { selectedTags.contains($0.id) }

        if let deck {
            deck.name = trimmed
            deck.colorHex = colorHex
            deck.tags = pickedTags
        } else {
            let d = Deck(name: trimmed, colorHex: colorHex)
            d.tags = pickedTags
            ctx.insert(d)
        }
        try? ctx.save()
        dismiss()
    }
}
