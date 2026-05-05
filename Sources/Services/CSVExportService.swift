import Foundation
import UniformTypeIdentifiers
import SwiftUI

enum CSVExportService {
    /// Builds a CSV string for a deck's cards.
    /// Columns: front, back, option1, option2, option3
    static func csvString(for deck: Deck) -> String {
        var lines = [#""front","back","option1","option2","option3""#]
        for c in deck.cards.sorted(by: { $0.createdAt < $1.createdAt }) {
            let cols = [c.front, c.back, c.option1 ?? "", c.option2 ?? "", c.option3 ?? ""]
                .map { field -> String in
                    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                    return "\"\(escaped)\""
                }
            lines.append(cols.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

/// FileDocument wrapper for CSV so SwiftUI's `.fileExporter` can save it.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var csvString: String

    init(_ csvString: String) { self.csvString = csvString }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents,
              let s = String(data: d, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.csvString = s
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(csvString.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
