import Foundation

enum ClaudeService {
    struct GeneratedCard {
        var front: String
        var back: String
        var option1: String?
        var option2: String?
        var option3: String?
    }

    enum ClaudeError: LocalizedError {
        case missingAPIKey
        case httpError(Int)
        case badResponse
        case noContent

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:  return "No Claude API key set. Add one in Settings."
            case .httpError(let c): return "API returned HTTP \(c). Check your key or quota."
            case .badResponse:    return "Unexpected response format from Claude."
            case .noContent:      return "Claude returned no cards. Try rephrasing the prompt."
            }
        }
    }

    static func generateCards(
        topic: String,
        count: Int,
        mode: GenerationMode,
        apiKey: String
    ) async throws -> [GeneratedCard] {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let prompt = buildPrompt(topic: topic, count: count, mode: mode)

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeError.httpError(http.statusCode)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first,
            let text = first["text"] as? String
        else { throw ClaudeError.badResponse }

        let cards = parseResponse(text)
        if cards.isEmpty { throw ClaudeError.noContent }
        return cards
    }

    enum GenerationMode: String, CaseIterable, Identifiable {
        case flashcard = "Flashcards (Q&A)"
        case mcq       = "MCQ (4 options)"
        var id: String { rawValue }
    }

    private static func buildPrompt(topic: String, count: Int, mode: GenerationMode) -> String {
        switch mode {
        case .flashcard:
            return """
You are an expert study-card creator. Generate exactly \(count) high-quality flashcards about the following topic or text passage.

Topic/Text:
\(topic)

Output ONLY a JSON array — no commentary, no markdown fences. Each element must have exactly:
  "front": <question or term as a string>,
  "back": <answer or definition as a string>

Be concise. Make each card test one specific fact. Output nothing except the JSON array.
"""
        case .mcq:
            return """
You are an expert MCQ question creator. Generate exactly \(count) multiple-choice questions about the following topic or text passage.

Topic/Text:
\(topic)

Output ONLY a JSON array — no commentary, no markdown fences. Each element must have exactly:
  "front": <question as a string>,
  "back": <correct answer text — short, e.g. "20 or more persons">,
  "option1": <wrong option 1 text>,
  "option2": <wrong option 2 text>,
  "option3": <wrong option 3 text>

Make the wrong options plausible. Output nothing except the JSON array.
"""
        }
    }

    private static func parseResponse(_ text: String) -> [GeneratedCard] {
        // Strip any accidental markdown fences
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().joined(separator: "\n")
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
        }

        guard
            let data = cleaned.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.compactMap { d -> GeneratedCard? in
            let s = { (key: String) -> String in (d[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            let front = s("front").nonEmpty ?? s("term").nonEmpty ?? s("question").nonEmpty
            let back  = s("back").nonEmpty  ?? s("answer").nonEmpty ?? s("definition").nonEmpty
            guard let f = front, let b = back else { return nil }
            return GeneratedCard(
                front: f, back: b,
                option1: s("option1").nonEmpty,
                option2: s("option2").nonEmpty,
                option3: s("option3").nonEmpty
            )
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
