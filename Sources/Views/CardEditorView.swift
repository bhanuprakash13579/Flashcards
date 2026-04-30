import SwiftUI
import SwiftData
import PhotosUI

struct CardEditorView: View {
    let deck: Deck
    let card: Card?

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var front = ""
    @State private var back = ""
    @State private var frontImageData: Data?
    @State private var backImageData: Data?
    @State private var frontPick: PhotosPickerItem?
    @State private var backPick: PhotosPickerItem?

    @FocusState private var focus: Field?
    private enum Field { case front, back }

    private var isEditing: Bool { card != nil }
    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespaces).isEmpty &&
        !back.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Front — question or term", text: $front, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focus, equals: .front)
                        .submitLabel(.next)
                        .onSubmit { focus = .back }
                    imageRow(
                        data: frontImageData,
                        pick: $frontPick,
                        placeholder: "Add front image (optional)",
                        onClear: { frontImageData = nil; frontPick = nil }
                    )
                } header: {
                    Text("Front")
                }

                Section {
                    TextField("Back — answer or definition", text: $back, axis: .vertical)
                        .lineLimit(2...8)
                        .focused($focus, equals: .back)
                    imageRow(
                        data: backImageData,
                        pick: $backPick,
                        placeholder: "Add back image (optional)",
                        onClear: { backImageData = nil; backPick = nil }
                    )
                } header: {
                    Text("Back")
                }

                if !isEditing {
                    Section {
                        Button("Save & add another") { save(stayOpen: true) }
                            .disabled(!canSave)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit card" : "New card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { save(stayOpen: false) }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadInitial)
            .onChange(of: frontPick) { _, item in
                Task { frontImageData = await loadCompressed(item) }
            }
            .onChange(of: backPick) { _, item in
                Task { backImageData = await loadCompressed(item) }
            }
        }
    }

    @ViewBuilder
    private func imageRow(data: Data?,
                          pick: Binding<PhotosPickerItem?>,
                          placeholder: String,
                          onClear: @escaping () -> Void) -> some View {
        if let data, let img = UIImage(data: data) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.s))
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(data.count / 1024) KB")
                        .font(.caption).foregroundStyle(.secondary)
                    PhotosPicker(selection: pick, matching: .images) {
                        Label("Replace", systemImage: "photo")
                    }
                    Button(role: .destructive, action: onClear) {
                        Label("Remove", systemImage: "trash")
                            .foregroundStyle(Theme.destructive)
                    }
                }
            }
            .padding(.vertical, 4)
        } else {
            PhotosPicker(selection: pick, matching: .images) {
                Label(placeholder, systemImage: "photo.badge.plus")
                    .foregroundStyle(Theme.focus)
            }
        }
    }

    private func loadCompressed(_ item: PhotosPickerItem?) async -> Data? {
        guard let item else { return nil }
        guard let raw = try? await item.loadTransferable(type: Data.self) else { return nil }
        return ImageCompressor.compress(raw)
    }

    private func loadInitial() {
        if let c = card {
            front = c.front
            back = c.back
            frontImageData = c.frontImageData
            backImageData = c.backImageData
        }
        focus = .front
    }

    private func save(stayOpen: Bool) {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !b.isEmpty else { return }

        if let card {
            card.front = f
            card.back = b
            card.frontImageData = frontImageData
            card.backImageData = backImageData
        } else {
            let new = Card(front: f, back: b, deck: deck)
            new.frontImageData = frontImageData
            new.backImageData = backImageData
            ctx.insert(new)
        }

        if stayOpen {
            front = ""
            back = ""
            frontImageData = nil
            backImageData = nil
            frontPick = nil
            backPick = nil
            focus = .front
        } else {
            dismiss()
        }
    }
}
