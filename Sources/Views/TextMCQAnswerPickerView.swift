import SwiftUI

/// Shown when a text/PDF MCQ file has questions whose correct answers couldn't be detected.
/// User taps the correct option for each question; tap auto-advances to the next.
struct TextMCQAnswerPickerView: View {
    let blocks: [RawMCQBlock]
    let onDone: ([CardSpec]) -> Void
    let onCancel: () -> Void

    @State private var index = 0
    @State private var selections: [String?]    // index-matched to blocks; pre-filled where detected

    init(blocks: [RawMCQBlock], onDone: @escaping ([CardSpec]) -> Void, onCancel: @escaping () -> Void) {
        self.blocks = blocks
        self.onDone = onDone
        self.onCancel = onCancel
        _selections = State(initialValue: blocks.map { $0.answer })
    }

    private var answeredCount: Int { selections.compactMap { $0 }.count }

    var body: some View {
        NavigationStack {
            if index >= blocks.count {
                doneScreen
            } else {
                questionScreen
            }
        }
        .navigationTitle("Pick Correct Answers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
        }
    }

    // MARK: - Done screen

    private var doneScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("All done!")
                .font(.title2.bold())
            Text("\(answeredCount) of \(blocks.count) answered")
                .foregroundStyle(.secondary)
            Button("Import \(answeredCount) cards") { onDone(buildSpecs()) }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Question screen

    private var questionScreen: some View {
        let block = blocks[index]
        return VStack(spacing: 0) {
            progressHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    questionCard(block)
                    optionButtons(block)
                    if let expl = block.explanation {
                        explanationBox(expl)
                    }
                }
                .padding()
            }
            navBar
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 4) {
            ProgressView(value: Double(index), total: Double(max(blocks.count, 1)))
                .padding(.horizontal)
                .padding(.top, 8)
            Text("\(index + 1) of \(blocks.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }

    private func questionCard(_ block: RawMCQBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let n = block.number {
                Text("Q\(n)").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Text(block.question)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func optionButtons(_ block: RawMCQBlock) -> some View {
        VStack(spacing: 10) {
            ForEach(block.options) { opt in
                Button {
                    selections[index] = opt.letter
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { advance() }
                } label: {
                    HStack(spacing: 12) {
                        let selected = selections[index] == opt.letter
                        Text(opt.letter)
                            .font(.headline)
                            .frame(width: 30, height: 30)
                            .background(selected ? Color.accentColor : Color(.tertiarySystemBackground))
                            .foregroundStyle(selected ? .white : .primary)
                            .clipShape(Circle())
                        Text(opt.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        selections[index] == opt.letter
                            ? Color.accentColor.opacity(0.1)
                            : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selections[index] == opt.letter ? Color.accentColor : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func explanationBox(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Explanation").font(.caption.bold()).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.primary)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var navBar: some View {
        HStack(spacing: 16) {
            if index > 0 {
                Button("Back") { index -= 1 }
                    .buttonStyle(.bordered)
            }
            Spacer()
            Button("Skip") { advance() }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
            if index < blocks.count - 1 {
                Button("Next") { advance() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Finish") { onDone(buildSpecs()) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Helpers

    private func advance() {
        if index < blocks.count { index += 1 }
    }

    private func buildSpecs() -> [CardSpec] {
        zip(blocks, selections).compactMap { block, letter in
            var b = block
            b.answer = letter
            return b.toCardSpec()
        }
    }
}
