import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .blue
            return
        }
        self = Color(
            red:   Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >>  8) & 0xFF) / 255.0,
            blue:  Double( v        & 0xFF) / 255.0
        )
    }
}

enum DeckPalette {
    static let colors: [String] = [
        "#4F8EF7", "#F76C6C", "#7BC47F", "#F7B84F",
        "#A77DFF", "#3FB8AF", "#FF7AB6", "#5C6BC0"
    ]
    static func random() -> String { colors.randomElement() ?? "#4F8EF7" }
}
