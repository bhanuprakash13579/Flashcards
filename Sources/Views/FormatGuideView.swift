import SwiftUI

struct FormatGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copiedKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    intro
                    csvSection
                    jsonQASection
                    jsonMCQExplicitSection
                    jsonMCQArrayLetterSection
                    jsonMCQArrayTextSection
                    jsonBackupSection
                    tipsSection
                }
                .padding()
            }
            .navigationTitle("Format Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Every format below can be pasted directly into the text box or picked as a file. The app auto-detects the correct format.")
                .font(.subheadline).foregroundStyle(.secondary)
            Label("Tap any example to copy it.", systemImage: "doc.on.doc")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - CSV / TSV

    private var csvSection: some View {
        guideSection(
            title: "CSV / TSV / Plain Text",
            icon: "tablecells",
            color: .blue,
            description: "One card per line. Columns are separated by Tab, Comma, Pipe (|), or double-colon (::). Lines starting with # are treated as comments and ignored.",
            examples: [
                GuideExample(
                    label: "Flashcards World Format (Default)",
                    note: "The recommended format! Header row is automatically ignored. Supports up to 3 optional distractors.",
                    code: """
Front,Back,Option1,Option2,Option3
What is the capital of France?,Paris,London,Berlin,Madrid
Which planet is known as the Red Planet?,Mars,Venus,Jupiter,Saturn
"""
                ),
                GuideExample(
                    label: "Q&A only (Tab-separated)",
                    note: "2 columns: front ↹ back",
                    code: """
What year was the EPF Act passed?\t1952
Minimum employees for EPF applicability\t20 or more persons
# This line is a comment and will be ignored
Capital of India\tNew Delhi
"""
                ),
                GuideExample(
                    label: "MCQ with wrong options (Comma-separated)",
                    note: "5 columns: front, back (correct), option1, option2, option3",
                    code: """
"EPF Act was passed in which year?","1952","1948","1956","1961"
"Minimum employees for EPF?","20 or more","10 or more","50 or more","100 or more"
"""
                ),
                GuideExample(
                    label: "Pipe-separated",
                    note: "Useful when text contains commas",
                    code: """
What does SM-2 stand for?|SuperMemo 2 algorithm
EPF full form|Employees' Provident Fund
"""
                ),
            ]
        )
    }

    // MARK: - JSON Q&A

    private var jsonQASection: some View {
        guideSection(
            title: "JSON — Simple Q&A",
            icon: "curlybraces",
            color: .orange,
            description: "An array of objects. The app accepts several key-name aliases for front and back.",
            examples: [
                GuideExample(
                    label: "Standard front / back",
                    note: nil,
                    code: """
[
  {"front": "What is the EPF Act?", "back": "Employees' Provident Fund Act 1952"},
  {"front": "Who administers EPFO?", "back": "Central Board of Trustees"}
]
"""
                ),
                GuideExample(
                    label: "term / definition aliases",
                    note: "Also works: question/answer, q/a",
                    code: """
[
  {"term": "SM-2", "definition": "Spaced repetition scheduling algorithm"},
  {"question": "Full form of APFC?", "answer": "Assistant Provident Fund Commissioner"}
]
"""
                ),
            ]
        )
    }

    // MARK: - JSON MCQ explicit options

    private var jsonMCQExplicitSection: some View {
        guideSection(
            title: "JSON — MCQ with Explicit Wrong Options",
            icon: "checkmark.square",
            color: .green,
            description: "The recommended MCQ format. back is the correct answer. option1/2/3 are the wrong options shown alongside it during practice.",
            examples: [
                GuideExample(
                    label: "MCQ — explicit option fields",
                    note: "back = correct answer, option1/2/3 = wrong options. During MCQ practice all 4 are shuffled and displayed.",
                    code: """
[
  {
    "front": "EPF Act applies to factories with how many employees?",
    "back": "20 or more persons",
    "option1": "10 or more persons",
    "option2": "50 or more persons",
    "option3": "100 or more persons"
  },
  {
    "front": "Which authority administers the EPF Scheme?",
    "back": "Central Board of Trustees",
    "option1": "Ministry of Finance",
    "option2": "SEBI",
    "option3": "RBI"
  }
]
"""
                ),
            ]
        )
    }

    // MARK: - JSON MCQ options array + letter answer

    private var jsonMCQArrayLetterSection: some View {
        guideSection(
            title: "JSON — MCQ options Array with Letter Answer",
            icon: "list.bullet",
            color: .purple,
            description: "Common export format from question banks. The app finds the correct option by letter (A/B/C/D) and automatically separates it from the wrong options.",
            examples: [
                GuideExample(
                    label: "options array + letter answer",
                    note: "answer can be: \"B\", \"(B)\", \"B.\", \"B)\"  — all formats accepted",
                    code: """
[
  {
    "question": "EPF Act was passed in which year?",
    "options": ["A. 1948", "B. 1952", "C. 1956", "D. 1961"],
    "answer": "B"
  },
  {
    "question": "Minimum employees for mandatory EPF registration?",
    "options": ["(A) 10", "(B) 20", "(C) 50", "(D) 100"],
    "answer": "(B)"
  }
]
"""
                ),
                GuideExample(
                    label: "options without letter prefixes",
                    note: "Plain option texts also work",
                    code: """
[
  {
    "question": "Whose fund does EPFO manage?",
    "options": ["Government employees", "Private sector employees", "Farmers", "Self-employed"],
    "answer": "Private sector employees"
  }
]
"""
                ),
            ]
        )
    }

    // MARK: - JSON MCQ options array + full-text answer

    private var jsonMCQArrayTextSection: some View {
        guideSection(
            title: "JSON — MCQ with Explanation",
            icon: "text.bubble",
            color: .teal,
            description: "If an explanation field is present it is appended to the answer shown on the card back.",
            examples: [
                GuideExample(
                    label: "question + options + answer + explanation",
                    note: "explanation / rationale fields are both accepted",
                    code: """
[
  {
    "question": "EPF Act minimum employees threshold?",
    "options": ["A. 10", "B. 20", "C. 50", "D. 100"],
    "answer": "B",
    "explanation": "S.1(3)(a): Act applies to every establishment employing 20 or more persons."
  }
]
"""
                ),
            ]
        )
    }

    // MARK: - Full backup format

    private var jsonBackupSection: some View {
        guideSection(
            title: "JSON — Full Backup / Library Export",
            icon: "externaldrive",
            color: .gray,
            description: "This is the format produced by Settings → Export backup. When imported in Bulk Import, all cards from all decks are merged into the current deck. To restore the full library with deck structure, use Settings → Import / Restore from file instead.",
            examples: [
                GuideExample(
                    label: "Backup format (generated by Settings → Export)",
                    note: "version, exportedAt, decks[] structure",
                    code: """
{
  "version": 2,
  "exportedAt": "2026-05-01T10:00:00Z",
  "decks": [
    {
      "id": "62e4bdf0-...",
      "name": "EPF Act 1952",
      "colorHex": "#4F8EF7",
      "createdAt": "2026-04-30T20:03:37Z",
      "cards": [
        {
          "id": "d634386c-...",
          "front": "EPF Act minimum employees?",
          "back": "20 or more persons",
          "option1": "10 or more persons",
          "option2": "50 or more persons",
          "option3": "100 or more persons",
          "box": 1,
          "nextReview": "2026-05-01T00:00:00Z",
          "createdAt": "2026-04-30T20:03:37Z",
          "correctCount": 0,
          "wrongCount": 0
        }
      ]
    }
  ]
}
"""
                ),
            ]
        )
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tips", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            tipRow("MCQ practice uses your stored options (option1/2/3). If none are stored, the app auto-generates distractors from other cards' answers.")
            tipRow("The back field is always the correct answer shown during MCQ practice — keep it short and precise.")
            tipRow("For the EPFO dataset, import using the Full Backup format from Settings, not Bulk Import.")
            tipRow("CSV headers are optional — the first column is always treated as front, second as back.")
            tipRow("Quizlet exports as tab-separated .txt — just pick Tab as delimiter and it works directly.")
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: - Reusable section builder

    private func guideSection(
        title: String,
        icon: String,
        color: Color,
        description: String,
        examples: [GuideExample]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            Text(description)
                .font(.subheadline).foregroundStyle(.secondary)

            ForEach(examples) { ex in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(ex.label).font(.caption.weight(.semibold))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = ex.code
                            copiedKey = ex.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedKey == ex.id { copiedKey = nil }
                            }
                        } label: {
                            Label(copiedKey == ex.id ? "Copied!" : "Copy",
                                  systemImage: copiedKey == ex.id ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(copiedKey == ex.id ? Theme.success : .accentColor)
                        }
                    }
                    if let note = ex.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(ex.code)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
                }
                .onTapGesture {
                    UIPasteboard.general.string = ex.code
                    copiedKey = ex.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedKey == ex.id { copiedKey = nil }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

private struct GuideExample: Identifiable {
    let id = UUID().uuidString
    let label: String
    let note: String?
    let code: String
}
