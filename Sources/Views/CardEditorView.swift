import SwiftUI
import SwiftData
import PhotosUI

private extension String {
    var nonEmptyOrNil: String? { isEmpty ? nil : self }
}

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
    @State private var option1 = ""
    @State private var option2 = ""
    @State private var option3 = ""
    @State private var explanation = ""
    @State private var showMCQOptions = false
    @State private var userDifficulty = 0

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

                Section {
                    TextField("Explanation context or rationale", text: $explanation, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Explanation (Optional)")
                } footer: {
                    Text("This text will display beautifully below the card after you answer.")
                }

                difficultySection
                mcqSection

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

    private var difficultySection: some View {
        Section {
            Picker("Classification", selection: $userDifficulty) {
                Text("Unclassified").tag(0)
                Text("Easy").tag(1)
                Text("Medium").tag(2)
                Text("Hard").tag(3)
            }
        } header: {
            Text("Difficulty")
        } footer: {
            Text("Tag cards to easily filter them during practice.")
        }
    }

    private var mcqSection: some View {
        Section {
            Toggle("Add MCQ wrong options", isOn: $showMCQOptions)
            if showMCQOptions {
                TextField("Wrong option 1", text: $option1, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Wrong option 2", text: $option2, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Wrong option 3 (optional)", text: $option3, axis: .vertical)
                    .lineLimit(1...3)
            }
        } header: {
            Text("Multiple choice options")
        } footer: {
            showMCQOptions
                ? Text("The correct answer is the Back field. Add 1–3 wrong options here; the practice mode will use them instead of randomly picking distractors.")
                : Text("Enable to set specific wrong answers shown during MCQ practice. Leave off to auto-generate distractors from other cards.")
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
            option1 = c.option1 ?? ""
            option2 = c.option2 ?? ""
            option3 = c.option3 ?? ""
            explanation = c.storedExplanation ?? ""
            showMCQOptions = c.option1 != nil || c.option2 != nil
            userDifficulty = c.userDifficulty
        }
        focus = .front
    }

    private func save(stayOpen: Bool) {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !f.isEmpty, !b.isEmpty else { return }

        let o1 = showMCQOptions ? option1.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil : nil
        let o2 = showMCQOptions ? option2.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil : nil
        let o3 = showMCQOptions ? option3.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil : nil
        let expl = explanation.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil

        if let card {
            card.front = f
            card.back = b
            card.frontImageData = frontImageData
            card.backImageData = backImageData
            card.option1 = o1
            card.option2 = o2
            card.option3 = o3
            card.storedExplanation = expl
            card.userDifficulty = userDifficulty
        } else {
            let new = Card(front: f, back: b, deck: deck)
            new.frontImageData = frontImageData
            new.backImageData = backImageData
            new.option1 = o1
            new.option2 = o2
            new.option3 = o3
            new.storedExplanation = expl
            new.userDifficulty = userDifficulty
            ctx.insert(new)
        }
        try? ctx.save()

        if stayOpen {
            front = ""
            back = ""
            frontImageData = nil
            backImageData = nil
            frontPick = nil
            backPick = nil
            option1 = ""
            option2 = ""
            option3 = ""
            explanation = ""
            userDifficulty = 0
            focus = .front
        } else {
            dismiss()
        }
    }
}
